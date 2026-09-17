namespace Workspace {
    /**
     * Interprets the CLI argument, if any, as either a folder to link as
     * the workspace root or a file to open with no folder linked at all —
     * `folder_path`/`file_path` come back mutually exclusive, both null
     * when no argument was given (a blank window, no tab, no sidebar
     * until "Open Folder…" links one). Touches the filesystem (needs to
     * know whether the given path is actually a directory), unlike the
     * plain string logic this used to be.
     */
    public static void resolve (string[] args, out string? folder_path, out string? file_path) {
        folder_path = null;
        file_path = null;

        if (args.length <= 1) {
            return;
        }

        var path = args[1];
        if (FileUtils.test (path, FileTest.IS_DIR)) {
            folder_path = path;
        } else {
            file_path = path;
        }
    }
}
