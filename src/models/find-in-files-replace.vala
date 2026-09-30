/**
 * Applies FindInFilesSearch's own regex (rebuilt from the query that
 * produced `result`, via its now-public build_regex()) directly against
 * each matched file's *current* on-disk content — a plain per-file
 * regex substitution (`GLib.Regex.replace_eval()`, the same "read a
 * fresh string, produce a new one" shape any batch text tool uses),
 * not a replay of `result`'s own stored match offsets: those are
 * char-offset/line-number bookkeeping for rendering FindResults' own
 * buffer, not something this needs to touch at all — re-matching fresh
 * sidesteps the byte/char-offset conversion `find-in-files-search.vala`
 * itself has to do, and, unlike GtkSourceSearchContext (see
 * CodeEditorSearch's own capture_groups() and its doc comment on why),
 * `MatchInfo` already exposes every capture group directly, so no
 * second re-match is needed to resolve `$1`-style replacement patterns
 * either.
 *
 * Two real safety/accuracy concerns, both handled here rather than left
 * to the caller:
 *
 * - A file modified on disk *after* the search that produced `result`
 *   ran is skipped outright (recorded in the returned
 *   FindInFilesReplaceResult.skipped_paths, left untouched) rather than
 *   blindly rewritten against what could now be a stale match. Checked
 *   against real mtime (FileAttribute.TIME_MODIFIED + TIME_MODIFIED_USEC,
 *   sub-second — a file re-saved within the same wall-clock second as
 *   the search would otherwise not register as "newer" at all),
 *   compared to FindInFilesResult.searched_at. Per file, not per batch:
 *   one file vanishing, losing permissions, or otherwise failing to
 *   read/write is recorded the same way (skipped_paths) rather than
 *   throwing and aborting every file after it in the same run() call —
 *   files already rewritten earlier in the loop stay rewritten, and the
 *   caller still gets a real, complete outcome for all of them.
 * - The caller (FindResults) needs to show the *real*, just-written
 *   text afterward, not the stale pre-replace preview — and specifically
 *   needs to know exactly where in that new text each replacement
 *   landed, to highlight it. Re-searching for it afterward would be
 *   both redundant and, in regex mode with capture-group references
 *   ($1/$2/…), genuinely ambiguous — there's no single fixed "new term"
 *   to search for, since each match can turn into different text. The
 *   position is captured for free instead, at the exact moment each
 *   replacement is written: replace_eval()'s own `res` StringBuilder is
 *   the new file content accumulating in real time, so `res.len` right
 *   before appending is already that insertion's own start offset.
 */
public class FindInFilesReplace : Object {
  public static FindInFilesReplaceResult run (FindInFilesResult result, string replacement) throws Error {
    var regex = FindInFilesSearch.build_regex (result.query);
    var pattern = ReplacePattern.parse (replacement, result.query.regex_enabled);
    var outcome = new FindInFilesReplaceResult ();

    foreach (var file in result.files) {
      // A file that vanished, lost permissions, or otherwise fails to
      // even be read is treated the same as one skipped for being
      // modified after the search — recorded, left untouched — rather
      // than letting the exception escape and abort the whole batch,
      // which would silently strand every file already rewritten by an
      // earlier iteration of this same loop with no outcome ever
      // reported for any of them.
      try {
        var info = File.new_for_path (file.path).query_info (
          FileAttribute.TIME_MODIFIED + "," + FileAttribute.TIME_MODIFIED_USEC, FileQueryInfoFlags.NONE
        );
        var modified_at = info.get_modification_date_time ();
        if (modified_at != null && modified_at.compare (result.searched_at) > 0) {
          outcome.skipped_paths.add (file.path);
          continue;
        }

        string contents;
        FileUtils.get_contents (file.path, out contents);

        var insertions = new GenericArray<ByteRange> ();
        // GCC warns here ("incompatible pointer type", const-qualification
        // only): glib-2.0.vapi's own RegexEvalCallback delegate doesn't
        // mark its MatchInfo parameter const, so Vala's generated C
        // trampoline for this closure never matches the real
        // GRegexEvalCallback typedef's `const GMatchInfo *` (gregex.h) no
        // matter how this closure itself is written — a vapi defect, not
        // fixable from the call site (same class of Vala-codegen
        // const-mismatch already left as-is elsewhere in this build,
        // e.g. gtk_widget_set_css_classes/g_subprocess_launcher_spawnv).
        // Purely cosmetic: g_regex_replace_eval() itself only ever reads
        // through the pointer, so the missing const has no real effect.
        string replaced = regex.replace_eval (contents, -1, 0, 0, (match_info, res) => {
          var groups = new string[match_info.get_match_count ()];
          for (int i = 0; i < groups.length; i++) {
            groups[i] = match_info.fetch (i) ?? "";
          }
          var replacement_text = pattern.build (groups);
          insertions.add (new ByteRange () { start = (int) res.len, length = replacement_text.length });
          res.append (replacement_text);
          return false; // false = keep going to the next match
        });

        if (replaced != contents) {
          FileUtils.set_contents (file.path, replaced);
        }
        outcome.new_matches_by_path[file.path] = matches_from_byte_ranges (replaced, insertions);
      } catch (Error e) {
        outcome.skipped_paths.add (file.path);
      }
    }

    return outcome;
  }

  /** One insertion's own [start, start + length) byte range within the new file content replace_eval() just built — never exposed past this file, see matches_from_byte_ranges() below. */
  private class ByteRange : Object {
    public int start;
    public int length;
  }

  /**
   * Converts each insertion's own byte range within `content` (the
   * file's real, already-written new content) into a FindInFilesMatch —
   * same byte->char column conversion FindInFilesSearch's own
   * search_file() already does per line, just resolved against
   * whole-file byte offsets here instead of per-line ones, since
   * replace_eval() only ever hands back offsets into the whole string.
   *
   * A replacement that itself inserts a literal newline (rare, but
   * possible via ReplacePattern's own `\n` escape) only ever shifts
   * line numbers for insertions *after* it in the same file — each
   * insertion is still correctly resolved against the same, single
   * fresh split of the final content, not the pre-replace line numbers
   * FindInFilesBlock.start_line was computed against; FindResults' own
   * refresh is what has to stay aware of that mismatch, not this method.
   */
  private static GenericArray<FindInFilesMatch> matches_from_byte_ranges (string content, GenericArray<ByteRange> ranges) {
    var matches = new GenericArray<FindInFilesMatch> ();
    var lines = content.split ("\n");

    // Cumulative byte offset of each line's own start — walked once here
    // rather than re-scanning from the top of the file for every
    // insertion below.
    var line_start_bytes = new int[lines.length];
    int cumulative = 0;
    for (int i = 0; i < lines.length; i++) {
      line_start_bytes[i] = cumulative;
      cumulative += lines[i].length + 1; // +1 for the '\n' split() itself consumed
    }

    foreach (var range in ranges) {
      int line_index = 0;
      for (int i = 0; i < lines.length; i++) {
        if (line_start_bytes[i] > range.start) {
          break;
        }
        line_index = i;
      }

      var line = lines[line_index];
      int start_in_line = int.min (range.start - line_start_bytes[line_index], line.length);
      // Clamped to this same line's own end — a replacement that
      // crosses into the next line (only possible if it inserted a
      // literal newline itself) still gets a real, in-bounds highlight
      // on its own start line rather than an out-of-range substring;
      // FindInFilesMatch itself has no notion of a multi-line match
      // anyway (neither does a plain search — see find-in-files-search.
      // vala's own search_file(), always scanned one line at a time).
      int end_in_line = int.min (start_in_line + range.length, line.length);

      var match = new FindInFilesMatch ();
      match.line_number = line_index + 1;
      match.start_column = line.substring (0, start_in_line).char_count ();
      match.end_column = line.substring (0, end_in_line).char_count ();
      matches.add (match);
    }

    return matches;
  }
}
