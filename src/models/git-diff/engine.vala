/**
 * Pure(-ish) line-diff engine: two `git diff --no-index -U0` subprocess
 * runs (against HEAD, then against the index) plus unified-diff-header
 * parsing, merged into one Hunk[]. Subprocess-based, not a hand-rolled
 * Myers/Histogram implementation — same "trust git as the oracle"
 * philosophy GitStatus/GitFileList already
 * establish, and it gives every hunk git's own real diff heuristics for
 * free.
 */
namespace GitDiff {
  public class Engine : Object {
    /**
     * `head_tmp_path`/`index_tmp_path`: paths to already-written temp
     * files holding HEAD/index content — null means "no base". Both
     * null (genuinely untracked, outside the repo, or outside the
     * linked workspace entirely) means there's nothing to compare
     * against at all: no hunks, matching VS Code's own choice to show
     * no gutter marks for an untracked file.
     *
     * Two independent, whole diffs, not one diff with a per-hunk
     * refinement — confirmed against VS Code's own real algorithm
     * (`quickDiffModel.ts`/`quickDiffDecorator.ts`): the index diff is
     * primary (always solid, existence and kind both come from it —
     * it's the most specific base there is), the HEAD diff is secondary
     * (candidate dimmed marks). A secondary hunk is dropped *entirely*
     * — not trimmed down to just its non-overlapping part — the moment
     * it so much as touches a primary hunk's range
     * (`LineRange.intersectsOrTouches`, confirmed in VS Code's own
     * `quickDiffDecorator.ts:149`), since at that point it's redundant:
     * whatever it would have shown is already covered, solid, by the
     * primary hunk. `current_text`: the live buffer content, piped via
     * stdin on every call — writing the base files is the caller's
     * (DocumentTracker's) job, done once per bases_changed, not here.
     */
    public static Hunk[] compute_hunks (string? head_tmp_path, string? index_tmp_path, string current_text) {
      var primary = index_tmp_path == null ? new Hunk[0] : compute_hunks_against (index_tmp_path, current_text);

      if (head_tmp_path == null) {
        return primary;
      }

      var head_hunks = compute_hunks_against (head_tmp_path, current_text);
      var secondary = new List<Hunk> ();
      foreach (var h in head_hunks) {
        if (!touches_any (primary, h)) {
          secondary.append (new Hunk (h.current_start, h.current_count, h.kind, false));
        }
      }

      var result = new Hunk[primary.length + secondary.length ()];
      int i = 0;
      foreach (var h in primary) {
        result[i++] = h;
      }
      foreach (var h in secondary) {
        result[i++] = h;
      }
      return result;
    }

    /**
     * `git diff --no-index` exits 1 (not 0) when it finds real
     * differences — only exit > 1 (or a non-exit) means it couldn't
     * diff at all. Deliberately NOT process.get_successful() (checks
     * for exit 0), which would discard every real hunk as if it were a
     * failure.
     */
    private static Hunk[] compute_hunks_against (string base_tmp_path, string current_text) {
      if (!HostCommand.has_program ("git")) {
        return {};
      }

      var launcher = new SubprocessLauncher (SubprocessFlags.STDIN_PIPE | SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_SILENCE);
      string[] argv = HostCommand.argv ({ "git", "diff", "--no-index", "-U0", "--no-color", base_tmp_path, "-" });

      Subprocess process;
      string? stdout_buf;
      try {
        process = launcher.spawnv (argv);
        process.communicate_utf8 (current_text, null, out stdout_buf, null);
      } catch (Error e) {
        return {};
      }

      if (!process.get_if_exited () || process.get_exit_status () > 1 || stdout_buf == null) {
        return {};
      }
      return parse_unified_diff (stdout_buf);
    }

    /** Public, not private: lets a test binary feed a fixed unified-diff string directly, with no subprocess/git involvement (and `internal` wouldn't cross the test library's boundary). */
    public static Hunk[] parse_unified_diff (string diff_output) {
      // A plain GLib.List, not a fixed-size array built up front: the
      // final hunk count isn't known until every line's been scanned,
      // and a GenericArray<Hunk> here hits a valac codegen mismatch
      // converting back to Hunk[] (Hunk isn't a simple/compact type).
      var found = new List<Hunk> ();
      foreach (var line in diff_output.split ("\n")) {
        if (!line.has_prefix ("@@ ")) {
          continue;
        }

        int old_count, new_start, new_count;
        if (!parse_hunk_header (line, out old_count, out new_start, out new_count)) {
          continue;
        }

        if (old_count == 0) {
          found.append (new Hunk (new_start - 1, new_count, HunkKind.ADDED, true));
        } else if (new_count == 0) {
          // No real current-buffer range for a pure deletion — new_start
          // (as reported, 1-based "after this many new-file lines") is
          // already the correct 0-based anchor for the line immediately
          // following the deletion point.
          found.append (new Hunk (new_start, 0, HunkKind.REMOVED, true));
        } else {
          found.append (new Hunk (new_start - 1, new_count, HunkKind.CHANGED, true));
        }
      }

      var result = new Hunk[found.length ()];
      int index = 0;
      foreach (var h in found) {
        result[index++] = h;
      }
      return result;
    }

    /** "@@ -oldStart[,oldCount] +newStart[,newCount] @@ ..." — hand-rolled, not GLib.Regex: this layer has no established regex-for-parsing precedent, and the format is simple/fixed enough that a manual scan reads clearer than a capture-group regex here. */
    private static bool parse_hunk_header (string line, out int old_count, out int new_start, out int new_count) {
      old_count = 0;
      new_start = 0;
      new_count = 0;

      var parts = line.split (" ");
      if (parts.length < 4) {
        return false;
      }

      int old_start;
      if (!parse_range_token (parts[1], '-', out old_start, out old_count)) {
        return false;
      }
      if (!parse_range_token (parts[2], '+', out new_start, out new_count)) {
        return false;
      }
      return true;
    }

    /** `token` is e.g. "-3,2" or "+5" (an omitted count defaults to 1). */
    private static bool parse_range_token (string token, char prefix, out int start, out int count) {
      start = 0;
      count = 1;

      if (token.length == 0 || token[0] != prefix) {
        return false;
      }

      var body = token.substring (1);
      var comma = body.index_of (",");
      if (comma < 0) {
        start = int.parse (body);
      } else {
        start = int.parse (body.substring (0, comma));
        count = int.parse (body.substring (comma + 1));
      }
      return true;
    }

    /** `LineRange.intersectsOrTouches`'s own check (`a.start <= b.end && b.start <= a.end`, using exclusive ends) — overlap OR direct adjacency, not just overlap. A REMOVED hunk (current_count == 0) has no real span; treated as a single-line point at current_start, same as hunk_covers_line's own REMOVED handling in CodeEditorChangeGutter. */
    private static bool touches_any (Hunk[] hunks, Hunk candidate) {
      var candidate_end = candidate.current_start + int.max (candidate.current_count, 1);
      foreach (var h in hunks) {
        var h_end = h.current_start + int.max (h.current_count, 1);
        if (candidate.current_start <= h_end && h.current_start <= candidate_end) {
          return true;
        }
      }
      return false;
    }
  }
}
