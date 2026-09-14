namespace Workspace {
    /**
     * Resolves the root path to browse: the CLI argument if one was given,
     * otherwise the current working directory. Pure and side-effect free —
     * no filesystem access, no normalization.
     */
    public static string resolve_root_path (string[] args, string cwd) {
        if (args.length > 1) {
            return args[1];
        }
        return cwd;
    }
}
