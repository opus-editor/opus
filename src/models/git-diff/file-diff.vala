namespace GitDiff {
  public enum LineKind {
    CONTEXT,
    ADDED,
    REMOVED;
  }

  /** One line of the inline diff: the text, which side(s) it is on, and its number on each (0 where it has none). */
  public class DiffLine : Object {
    public LineKind kind { get; construct; }
    public int old_number { get; construct; }
    public int new_number { get; construct; }
    public string text { get; construct; }

    public DiffLine (LineKind kind, int old_number, int new_number, string text) {
      Object (kind: kind, old_number: old_number, new_number: new_number, text: text);
    }
  }

  /**
   * The whole file, inline: every line of the right side in order, with
   * the lines the left side lost slotted in where they were — what the
   * diff tab shows, every line with its old and new number. Computed by
   * git itself (`git diff --no-index`, the two sides as temp files, a
   * context wide enough to cover the whole file), not an in-process
   * algorithm — same "git is the oracle" reasoning as GitDiff.Engine.
   */
  public class FileDiff : Object {
    public GenericArray<DiffLine> lines = new GenericArray<DiffLine> ();
    public int added_count = 0;
    public int removed_count = 0;
    /** git's "\ No newline at end of file", per side. */
    public bool left_no_newline = false;
    public bool right_no_newline = false;

    public static FileDiff compute (string left_text, string right_text) throws GitScope.CommandError {
      if (left_text == right_text) {
        return identical (right_text);
      }
      if (!HostCommand.has_program ("git")) {
        throw new GitScope.CommandError.NOT_AVAILABLE ("Git isn’t installed, or isn’t on this computer’s PATH.");
      }
      string dir;
      string left_path;
      string right_path;
      try {
        dir = DirUtils.mkdtemp (Path.build_filename (HostCommand.shared_tmp_dir ("git"), "opus-file-diff-XXXXXX"));
        left_path = Path.build_filename (dir, "left");
        right_path = Path.build_filename (dir, "right");
        FileUtils.set_contents (left_path, left_text);
        FileUtils.set_contents (right_path, right_text);
      } catch (Error e) {
        throw new GitScope.CommandError.FAILED (e.message);
      }
      try {
        int context = int.max (count_lines (left_text), count_lines (right_text)) + 1;
        return parse_unified (run_git_diff (left_path, right_path, context));
      } finally {
        FileUtils.remove (left_path);
        FileUtils.remove (right_path);
        DirUtils.remove (dir);
      }
    }

    public static async FileDiff compute_async (string left_text, string right_text) throws GitScope.CommandError {
      FileDiff? result = null;
      yield GitScope.Command.in_thread (() => {
        result = compute (left_text, right_text);
      });
      return result;
    }

    /** Both sides the same: every line is context, numbered the same on both. */
    private static FileDiff identical (string text) {
      var diff = new FileDiff ();
      if (text == "") {
        return diff;
      }
      var raw_lines = text.split ("\n");
      int count = text.has_suffix ("\n") ? raw_lines.length - 1 : raw_lines.length;
      for (int i = 0; i < count; i++) {
        diff.lines.add (new DiffLine (LineKind.CONTEXT, i + 1, i + 1, strip_cr (raw_lines[i])));
      }
      diff.left_no_newline = diff.right_no_newline = !text.has_suffix ("\n");
      return diff;
    }

    /** `git diff --no-index` exits 1 when the files differ — only exit > 1 is a failure (see GitDiff.Engine). */
    private static string run_git_diff (string left_path, string right_path, int context) throws GitScope.CommandError {
      var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE);
      string[] argv = HostCommand.argv ({ "git", "diff", "--no-index", "--no-color", "--unified=%d".printf (context), left_path, right_path });
      Subprocess process;
      string? stdout_buf;
      string? stderr_buf;
      try {
        process = launcher.spawnv (argv);
        process.communicate_utf8 (null, null, out stdout_buf, out stderr_buf);
      } catch (Error e) {
        throw new GitScope.CommandError.NOT_AVAILABLE (e.message);
      }
      if (!process.get_if_exited () || process.get_exit_status () > 1) {
        throw new GitScope.CommandError.FAILED ("$ git diff --no-index\n%s".printf ((stderr_buf ?? "").strip ()));
      }
      return stdout_buf ?? "";
    }

    /**
     * Unified diff text → lines. Public so a test can feed a fixed diff
     * with no git involved. Everything before the first `@@` (the file
     * header) is skipped; a `\ No newline at end of file` line belongs to
     * the side(s) of the line just before it.
     */
    public static FileDiff parse_unified (string diff_text) {
      var diff = new FileDiff ();
      int old_number = 0;
      int new_number = 0;
      bool in_hunk = false;
      DiffLine? previous = null;
      foreach (var raw in diff_text.split ("\n")) {
        if (raw.has_prefix ("@@ ")) {
          in_hunk = true;
          int old_count, new_start, new_count, old_start;
          parse_hunk_starts (raw, out old_start, out old_count, out new_start, out new_count);
          old_number = old_start - 1;
          new_number = new_start - 1;
          continue;
        }
        if (!in_hunk || raw == "") {
          continue;
        }
        char marker = raw[0];
        var text = strip_cr (raw.substring (1));
        if (marker == '\\') {
          if (previous != null && previous.kind != LineKind.ADDED) {
            diff.left_no_newline = true;
          }
          if (previous != null && previous.kind != LineKind.REMOVED) {
            diff.right_no_newline = true;
          }
          continue;
        }
        if (marker == '+') {
          previous = new DiffLine (LineKind.ADDED, 0, ++new_number, text);
          diff.added_count++;
        } else if (marker == '-') {
          previous = new DiffLine (LineKind.REMOVED, ++old_number, 0, text);
          diff.removed_count++;
        } else if (marker == ' ') {
          previous = new DiffLine (LineKind.CONTEXT, ++old_number, ++new_number, text);
        } else {
          continue; // not a diff line (a stray header past a hunk)
        }
        diff.lines.add (previous);
      }
      return diff;
    }

    /** "@@ -oldStart[,oldCount] +newStart[,newCount] @@" — same shape GitDiff.Engine parses, with the old start kept too. */
    private static void parse_hunk_starts (string line, out int old_start, out int old_count, out int new_start, out int new_count) {
      old_start = 1;
      old_count = 0;
      new_start = 1;
      new_count = 0;
      var parts = line.split (" ");
      if (parts.length < 4) {
        return;
      }
      parse_range (parts[1], out old_start, out old_count);
      parse_range (parts[2], out new_start, out new_count);
    }

    private static void parse_range (string token, out int start, out int count) {
      start = 1;
      count = 1;
      var body = token.substring (1);
      var comma = body.index_of (",");
      if (comma < 0) {
        start = int.parse (body);
      } else {
        start = int.parse (body.substring (0, comma));
        count = int.parse (body.substring (comma + 1));
      }
      // git's "+0,0" for an empty side: the next line is still line 1
      if (start == 0) {
        start = 1;
      }
    }

    private static string strip_cr (string line) {
      return line.has_suffix ("\r") ? line.substring (0, line.length - 1) : line;
    }

    private static int count_lines (string text) {
      int count = 0;
      for (int i = 0; i < text.length; i++) {
        if (text[i] == '\n') {
          count++;
        }
      }
      return text.length > 0 && !text.has_suffix ("\n") ? count + 1 : count;
    }
  }
}
