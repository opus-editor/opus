namespace GitDiff {
  public enum BlobStatus {
    OK,
    /** A NUL byte in the first bytes — VS Code's own sniff (encoding.ts). */
    BINARY,
    /** Past MAX_BYTES — a diff this big isn't shown, same as VS Code's diffEditor.maxFileSize. */
    TOO_LARGE,
    NOT_UTF8,
    /** The revision has no such path, or the file isn't on disk. */
    MISSING,
    /** A symlink or a submodule — neither has text to diff. */
    UNSUPPORTED;
  }

  /** One side's text, or why there is none. */
  public class BlobResult : Object {
    public BlobStatus status { get; construct; }
    public string text { get; construct; default = ""; }

    public BlobResult (BlobStatus status, string text = "") {
      Object (status: status, text: text);
    }
  }

  /** Reads a Side's text: `git show --textconv rev:path` for a revision (textconv honours the repository's own gitattributes filters, as VS Code does), the file itself for the working tree. */
  public class Blob : Object {
    public const int64 MAX_BYTES = 5 * 1024 * 1024;
    private const int SNIFF_BYTES = 8000;

    public static BlobResult read (string root_path, Side side) {
      switch (side.kind) {
        case SideKind.EMPTY: return new BlobResult (BlobStatus.OK, "");
        case SideKind.WORKTREE: return read_file (side.path);
        default: return read_revision (root_path, side);
      }
    }

    private static BlobResult read_file (string path) {
      if (FileUtils.test (path, FileTest.IS_SYMLINK) || FileUtils.test (path, FileTest.IS_DIR)) {
        return new BlobResult (BlobStatus.UNSUPPORTED);
      }
      if (!FileUtils.test (path, FileTest.IS_REGULAR)) {
        return new BlobResult (BlobStatus.MISSING);
      }
      try {
        var info = File.new_for_path (path).query_info (FileAttribute.STANDARD_SIZE, FileQueryInfoFlags.NONE);
        if (info.get_size () > MAX_BYTES) {
          return new BlobResult (BlobStatus.TOO_LARGE);
        }
        uint8[] contents;
        FileUtils.get_data (path, out contents);
        return classify (contents);
      } catch (Error e) {
        return new BlobResult (BlobStatus.MISSING);
      }
    }

    private static BlobResult read_revision (string root_path, Side side) {
      if (!HostCommand.has_program ("git")) {
        return new BlobResult (BlobStatus.MISSING);
      }
      var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_SILENCE);
      string[] argv = HostCommand.argv ({ "git", "--no-optional-locks", "-C", root_path, "show", "--textconv", "%s:%s".printf (side.revision, side.path) });
      Subprocess process;
      Bytes? stdout_buf;
      try {
        process = launcher.spawnv (argv);
        process.communicate (null, null, out stdout_buf, null);
      } catch (Error e) {
        return new BlobResult (BlobStatus.MISSING);
      }
      if (!process.get_successful () || stdout_buf == null) {
        return new BlobResult (BlobStatus.MISSING);
      }
      if (stdout_buf.get_size () > MAX_BYTES) {
        return new BlobResult (BlobStatus.TOO_LARGE);
      }
      unowned uint8[] data = stdout_buf.get_data ();
      // A gitlink (submodule entry) shows as this one line rather than failing.
      if (data.length > 0 && ((string) data).has_prefix ("Subproject commit ")) {
        return new BlobResult (BlobStatus.UNSUPPORTED);
      }
      return classify (data);
    }

    private static BlobResult classify (uint8[] data) {
      int limit = int.min (data.length, SNIFF_BYTES);
      for (int i = 0; i < limit; i++) {
        if (data[i] == 0) {
          return new BlobResult (BlobStatus.BINARY);
        }
      }
      var text = (string) data;
      if (data.length > 0 && !text.validate (data.length)) {
        return new BlobResult (BlobStatus.NOT_UTF8);
      }
      return new BlobResult (BlobStatus.OK, data.length == 0 ? "" : text.substring (0, data.length));
    }
  }
}
