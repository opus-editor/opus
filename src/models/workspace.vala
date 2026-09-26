namespace Workspace {
  /**
   * Interprets the CLI argument, if any, as either a folder to link as
   * the workspace root or a file to open with no folder linked at all —
   * `folder_path`/`file_path` come back mutually exclusive, both null
   * when no argument was given (a blank window, no tab, no sidebar
   * until "Open Folder…" links one). Touches the filesystem (needs to
   * know whether the given path is actually a directory), unlike the
   * plain string logic this used to be.
   *
   * Always resolved to an absolute path — `opus .`/`opus justfile` (a
   * relative argument) would otherwise leave every FileNode built under
   * it relative too (FileTree just concatenates paths, it doesn't
   * resolve them), which then surfaced as far as a tab's own tooltip
   * showing something relative instead of a real absolute path.
   * `Gio.File.new_for_path().get_path()` already does exactly this
   * (confirmed directly, not assumed: it resolves a relative argument
   * against the process's own cwd) — simpler than reimplementing path
   * resolution by hand.
   */
  public static void resolve (string[] args, out string? folder_path, out string? file_path) {
    folder_path = null;
    file_path = null;

    if (args.length <= 1) {
      return;
    }

    // get_path() is nullable in general (a File isn't always backed by
    // a local path), but always non-null for one built via
    // new_for_path() specifically — the fallback is just to satisfy
    // null-safety, not because this is expected to matter in practice.
    var path = File.new_for_path (args[1]).get_path () ?? args[1];
    if (FileUtils.test (path, FileTest.IS_DIR)) {
      folder_path = path;
    } else {
      file_path = path;
    }
  }
}
