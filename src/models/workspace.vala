namespace Workspace {
  /**
   * Interprets the CLI argument, if any, as either a folder to link as
   * the workspace root or a file to open with no folder linked at all —
   * `folder_path`/`file_path` come back mutually exclusive, both null
   * when no argument was given (a blank window, no tab, no sidebar
   * until "Open Folder…" links one). Touches the filesystem: it needs
   * to know whether the given path is actually a directory.
   *
   * Always resolved to an absolute path — `opus .`/`opus justfile` (a
   * relative argument) would otherwise leave every FileNode built under
   * it relative too (FileTree just concatenates paths, it doesn't
   * resolve them), which then surfaced as far as a tab's own tooltip
   * showing something relative instead of a real absolute path.
   *
   * A relative argument is taken from `cwd`, the directory the command
   * was typed in — not this process's own: with an Opus already open,
   * the command runs over here, wherever this process was started.
   */
  public static void resolve (string[] args, string cwd, out string? folder_path, out string? file_path) {
    folder_path = null;
    file_path = null;

    if (args.length <= 1) {
      return;
    }

    // get_path() is nullable in general (a File isn't always backed by
    // a local path), but always non-null for one built from a path — the
    // fallback is just to satisfy null-safety.
    var path = File.new_for_path (cwd).resolve_relative_path (args[1]).get_path () ?? args[1];
    if (FileUtils.test (path, FileTest.IS_DIR)) {
      folder_path = path;
    } else {
      file_path = path;
    }
  }
}
