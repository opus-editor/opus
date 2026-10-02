/**
 * Find in Files' own actual search: walks `root_path`, reads every
 * regular file it finds, and returns every live match grouped by file
 * and merged into contiguous display blocks (a matched line plus
 * `context_lines` lines before/after, merged with any neighboring
 * match's own window once they touch or overlap).
 *
 * `query.gitignore_enabled` doesn't hand-parse `.gitignore` — it shells
 * out to a real `git ls-files` (see git_tracked_files()'s own doc
 * comment) and walks *that* flat list instead of recursing into every
 * directory itself, so an ignored subtree (a `node_modules/`,
 * `builddir/`, …) is never even listed, let alone read — checked
 * against how VS Code's own real search does this (its ripgrep path
 * hands the exact same job to ripgrep's own native gitignore support;
 * its pure-JS fallback, `IgnoreFile` in ignoreFile.ts, only exists at
 * all because that path also has to run inside a browser tab with no
 * way to spawn `git` — a constraint this native app doesn't have, so
 * there's no reason to hand-roll the same parsing work here).
 * Unavailable (not a git repo, or `git` itself missing) falls back to
 * the plain recursive walk, silently — same as the toggle being off.
 *
 * `query.where_text` is a completely separate, file-level check — see
 * FindInFilesScope's own doc comment for its grammar (deliberately the
 * same idiom as `.gitignore`, just with the opposite include/exclude
 * polarity) — applied identically regardless of which of the two walks
 * above found the file.
 *
 * `run()` is a plain synchronous function — no Gtk/Adw, no threading of
 * its own, independently unit-testable with real files on disk (see
 * `tests/models/find-in-files-search-test.vala`). `run_async()` is the
 * one place in this whole feature (and the first in this codebase) a
 * background thread gets spawned, since a big enough tree would
 * otherwise block the UI thread for real — EditorView.EditorPane.TabFindResults.search()
 * awaits it directly and never touches Gtk/Adw off the main thread
 * itself.
 */
public class FindInFilesSearch : Object {
  // Same exclusion FileTree already uses — never useful to search, and
  // walking a real repo's own .git/objects would dwarf everything else.
  // Only matters for the plain recursive walk — git_tracked_files()'s
  // own flat list never includes .git's own contents in the first place.
  private const string EXCLUDED_ENTRY = ".git";
  private const string ENTRY_ATTRIBUTES =
    FileAttribute.STANDARD_NAME + "," + FileAttribute.STANDARD_TYPE + "," + FileAttribute.STANDARD_IS_SYMLINK;

  // Same order of magnitude as VS Code's own real cap (MATCHES_LIMIT,
  // findModel.ts) — a safety valve against a broad query on a huge tree
  // hanging the app, not a feature in its own right.
  private const int MAX_MATCHES = 20000;

  /** Synchronous core — see the class's own doc comment for why this is kept separate from run_async(). */
  public static FindInFilesResult run (string root_path, FindInFilesQuery query, int context_lines) throws Error {
    var regex = build_regex (query);
    var scope = new FindInFilesScope (query.where_text);

    var result = new FindInFilesResult ();
    result.query = query;
    result.context_lines = context_lines;
    // Captured before the walk, not after — a file already covered by
    // the time it was touched mid-walk should still count as "possibly
    // changed since", the conservative direction for FindInFilesReplace's
    // own later safety check.
    result.searched_at = new DateTime.now_local ();

    string[]? tracked_files = query.gitignore_enabled ? git_tracked_files (root_path) : null;
    if (tracked_files != null) {
      search_tracked_files (tracked_files, root_path, scope, regex, context_lines, result);
    } else {
      walk_directory (root_path, root_path, scope, regex, context_lines, result);
    }
    return result;
  }

  /** `path` (absolute) relative to `root_path` — same idiom EditorPaneWidget's own relative_path() already uses for "Copy Relative Path". */
  private static string relative_to_root (string root_path, string path) {
    var prefix = root_path + "/";
    return path.has_prefix (prefix) ? path.substring (prefix.length) : path;
  }

  /**
   * Every path `git -C root_path ls-files --cached --others --exclude-
   * standard` itself lists — every tracked file, plus every untracked
   * one that isn't hidden by a `.gitignore`, `.git/info/exclude`, or the
   * user's own global `core.excludesFile` (`--exclude-standard` covers
   * all three at once, more than a `.gitignore`-only parser would). A
   * real git subprocess, not a hand-rolled pattern matcher — see the
   * class's own doc comment for why. Plain newline-separated output
   * (git's own default), not `-z`/NUL-separated: Vala has no way to
   * spell a literal NUL as a string.split() delimiter (a `"\0"` literal
   * is already an empty C string by the time it gets there — confirmed
   * live, g_strsplit() itself rejects an empty delimiter outright), and
   * this codebase already assumes `\n` as the line separator everywhere
   * else (search_file()'s own contents.split ("\n")) — a path containing
   * a literal newline is already unsupported by this same assumption
   * elsewhere, not a new limitation introduced here.
   *
   * null whenever this can't answer at all — no `git` on PATH, or
   * `root_path` isn't inside a git repository (git itself reports that
   * failure; nothing upstream needs to detect it separately) — the
   * caller's own fallback (search everything, ignoring nothing) is what
   * "gitignore_enabled with no real answer available" means.
   */
  private static string[]? git_tracked_files (string root_path) {
    if (Environment.find_program_in_path ("git") == null) {
      return null;
    }

    var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_SILENCE);
    string[] argv = { "git", "-C", root_path, "ls-files", "--cached", "--others", "--exclude-standard" };

    Subprocess process;
    string? stdout_buf;
    try {
      process = launcher.spawnv (argv);
      process.communicate_utf8 (null, null, out stdout_buf, null);
    } catch (Error e) {
      return null;
    }

    if (!process.get_successful () || stdout_buf == null) {
      return null; // not inside a git repository, or some other git-level failure
    }

    var paths = new GenericArray<string> ();
    foreach (var relative_path in stdout_buf.split ("\n")) {
      if (relative_path != "") {
        paths.add (Path.build_filename (root_path, relative_path));
      }
    }

    // Same determinism guarantee walk_directory()'s own entry_names.
    // sort() gives the plain recursive walk.
    paths.sort (strcmp);
    var result = new string[paths.length];
    for (uint i = 0; i < paths.length; i++) {
      result[i] = paths[i];
    }
    return result;
  }

  /**
   * Same per-file search + MAX_MATCHES bookkeeping walk_directory() does
   * below, just driven by an already-known flat file list instead of
   * recursing into every directory itself — see git_tracked_files()'s
   * own doc comment for why that list already excludes whole ignored
   * subtrees before this ever runs, rather than reading them and
   * filtering the result away afterward.
   */
  private static void search_tracked_files (string[] paths, string root_path, FindInFilesScope scope, Regex regex, int context_lines, FindInFilesResult result) {
    foreach (var path in paths) {
      if (result.truncated) {
        return;
      }

      if (!scope.is_path_included (relative_to_root (root_path, path))) {
        continue;
      }

      FileInfo info;
      try {
        info = File.new_for_path (path).query_info (FileAttribute.STANDARD_IS_SYMLINK, FileQueryInfoFlags.NONE);
      } catch (Error e) {
        continue; // vanished between git listing it and stat-ing it, or unreadable — skip
      }
      if (info.get_is_symlink ()) {
        continue; // same as walk_directory's own — no cycle-following in v1
      }

      var file_result = search_file (path, regex, context_lines);
      if (file_result == null) {
        continue;
      }
      if (record_file_result (file_result, result)) {
        return;
      }
    }
  }

  /** Adds `file_result` to `result` and applies the MAX_MATCHES cap — shared by walk_directory()'s own per-file case and search_tracked_files()'s, so that threshold check only ever lives in one place. Returns whether the search just got truncated. */
  private static bool record_file_result (FindInFilesFileResult file_result, FindInFilesResult result) {
    result.files.add (file_result);
    result.total_match_count += file_result.match_count;
    if (result.total_match_count >= MAX_MATCHES) {
      result.truncated = true;
      return true;
    }
    return false;
  }

  /**
   * Runs run() on a background thread, resolving back on the main
   * loop — plain GLib (Thread/Idle), nothing Gtk/Adw involved, safe to
   * call from a View. EditorView.EditorPane.TabFindResults.search() is what actually
   * awaits this.
   */
  public static async FindInFilesResult run_async (string root_path, FindInFilesQuery query, int context_lines) throws Error {
    SourceFunc callback = run_async.callback;
    FindInFilesResult? result = null;
    Error? error = null;

    new Thread<void> ("find-in-files", () => {
      try {
        result = run (root_path, query, context_lines);
      } catch (Error e) {
        error = e;
      }
      Idle.add ((owned) callback);
    });

    yield;

    if (error != null) {
      throw error;
    }
    return result;
  }

  /** Public — FindInFilesReplace reuses this to match the exact same pattern run() searched with, rather than re-deriving it from scratch. */
  public static Regex build_regex (FindInFilesQuery query) throws RegexError {
    var pattern = query.regex_enabled ? query.text : Regex.escape_string (query.text);
    if (query.whole_word_enabled) {
      pattern = "\\b(?:%s)\\b".printf (pattern);
    }

    var flags = query.case_sensitive_enabled ? 0 : RegexCompileFlags.CASELESS;
    return new Regex (pattern, flags);
  }

  /**
   * `scope` is only ever checked against *files* here, never used to
   * prune a directory before recursing into it — a known v1
   * simplification (see FindInFilesScope's own doc comment for the
   * grammar): scoping to e.g. `/src` still walks every other top-level
   * directory in full, just discarding what it finds there at the
   * file-level check below, rather than skipping them outright. Doesn't
   * reintroduce the performance problem gitignore_enabled solves
   * (walking a huge generated tree) since a "Where" scope only ever
   * narrows what's kept, never widens what's walked.
   */
  private static void walk_directory (string dir_path, string root_path, FindInFilesScope scope, Regex regex, int context_lines, FindInFilesResult result) {
    Dir dir;
    try {
      dir = Dir.open (dir_path);
    } catch (Error e) {
      return; // unreadable directory (permissions, etc.) — skip, not fatal to the whole search
    }

    var entry_names = new GenericArray<string> ();
    string? entry_name;
    while ((entry_name = dir.read_name ()) != null) {
      if (entry_name == EXCLUDED_ENTRY) {
        continue;
      }
      entry_names.add (entry_name);
    }
    entry_names.sort (strcmp);

    for (uint i = 0; i < entry_names.length; i++) {
      if (result.truncated) {
        return;
      }

      var entry_path = Path.build_filename (dir_path, entry_names[i]);
      FileInfo info;
      try {
        info = File.new_for_path (entry_path).query_info (ENTRY_ATTRIBUTES, FileQueryInfoFlags.NONE);
      } catch (Error e) {
        continue; // vanished between listing and stat-ing, or unreadable — skip
      }

      if (info.get_is_symlink ()) {
        continue; // no cycle-following in v1 — see the plan's own non-goals
      }

      if (info.get_file_type () == FileType.DIRECTORY) {
        walk_directory (entry_path, root_path, scope, regex, context_lines, result);
        continue;
      }

      if (!scope.is_path_included (relative_to_root (root_path, entry_path))) {
        continue;
      }

      var file_result = search_file (entry_path, regex, context_lines);
      if (file_result == null) {
        continue;
      }
      if (record_file_result (file_result, result)) {
        return;
      }
    }
  }

  /** Every live match in `path`, grouped into blocks — null if `path` is binary/unreadable, or simply has no match. */
  private static FindInFilesFileResult? search_file (string path, Regex regex, int context_lines) {
    string contents;
    size_t length;
    try {
      FileUtils.get_contents (path, out contents, out length);
    } catch (Error e) {
      return null;
    }
    // Same UTF-8-validate-or-skip idiom Document.read_from_disk() already
    // uses for binary detection (document.vala) — a search has nothing
    // useful to report on content that isn't real text.
    if (!((string) contents).validate ((ssize_t) length)) {
      return null;
    }

    var lines = contents.split ("\n");
    var matches = new GenericArray<FindInFilesMatch> ();

    for (int i = 0; i < lines.length; i++) {
      var line = lines[i];
      int search_from = 0;
      while (search_from <= line.length) {
        MatchInfo match_info;
        bool found;
        try {
          found = regex.match_full (line, -1, search_from, 0, out match_info);
        } catch (RegexError e) {
          break; // pathological input for this one line — stop scanning it, keep whatever matched so far
        }
        if (!found) {
          break;
        }

        int match_start, match_end;
        match_info.fetch_pos (0, out match_start, out match_end);

        var match = new FindInFilesMatch ();
        match.line_number = i + 1;
        // fetch_pos() returns byte offsets; Gtk.TextIter (what these
        // ultimately drive once rendered) is char-based — substring()
        // is itself byte-offset-based, so this converts byte -> char
        // without assuming ASCII.
        match.start_column = line.substring (0, match_start).char_count ();
        match.end_column = line.substring (0, match_end).char_count ();
        matches.add (match);

        // Guard against a zero-width match (e.g. a regex like "a*")
        // looping forever on the same position.
        search_from = match_end > match_start ? match_end : match_end + 1;
      }
    }

    if (matches.length == 0) {
      return null;
    }

    var file_result = new FindInFilesFileResult ();
    file_result.path = path;
    file_result.match_count = (int) matches.length;
    file_result.blocks = merge_into_blocks (lines, matches, context_lines);
    return file_result;
  }

  private class LineRange {
    public int lo;
    public int hi;
    public GenericArray<FindInFilesMatch> matches = new GenericArray<FindInFilesMatch> ();
  }

  /** Expands each matched line into a [line-context, line+context] window (clamped to the file's own bounds), then sweep-merges any windows that touch or overlap — the same line is never shown twice within one file, and a merged window carries every match that lands on any of its lines. */
  private static GenericArray<FindInFilesBlock> merge_into_blocks (string[] lines, GenericArray<FindInFilesMatch> matches, int context_lines) {
    // One range per match, unmerged — the sort+sweep below is already a
    // complete, correct merge on its own; scanning for a mergeable
    // target here too would be strictly redundant work thrown away by
    // that same sort+sweep right after, not a real optimization.
    var ranges = new GenericArray<LineRange> ();
    for (uint i = 0; i < matches.length; i++) {
      var match = matches[i];
      var range = new LineRange ();
      range.lo = int.max (1, match.line_number - context_lines);
      range.hi = int.min (lines.length, match.line_number + context_lines);
      range.matches.add (match);
      ranges.add (range);
    }

    // Ranges were built in match order, not line order, and a later
    // match can still widen an earlier range past a range that comes
    // after it in `ranges` — sort, then merge adjacent/overlapping ones
    // for real before turning them into blocks.
    ranges.sort ((a, b) => a.lo - b.lo);
    var merged = new GenericArray<LineRange> ();
    foreach (var range in ranges) {
      if (merged.length > 0 && range.lo <= merged[merged.length - 1].hi + 1) {
        var last = merged[merged.length - 1];
        last.hi = int.max (last.hi, range.hi);
        foreach (var match in range.matches) {
          last.matches.add (match);
        }
      } else {
        merged.add (range);
      }
    }

    var blocks = new GenericArray<FindInFilesBlock> ();
    foreach (var range in merged) {
      var block = new FindInFilesBlock ();
      block.start_line = range.lo;
      block.lines = lines[range.lo - 1 : range.hi];
      block.matches = range.matches;
      blocks.add (block);
    }
    return blocks;
  }
}
