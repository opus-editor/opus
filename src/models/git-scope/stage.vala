/**
 * The write half of this namespace — `git add`/`git restore --staged`,
 * the mutations GitScope.StatusQuery/WorkingTree only ever read the
 * result of. GitView.StagingPane's own Stage/Unstage buttons. A
 * failure surfaces as GitScope.CommandError (see GitScope.Command).
 */
namespace GitScope {
  public class Stage : Object {
    /** Stages exactly `paths` (absolute) as they currently are in the worktree — untracked, modified or deleted alike. Nothing happens with an empty `paths`. */
    public static void add (string root_path, string[] paths) throws CommandError {
      Command.run_on_paths (root_path, { "add", "--" }, paths);
    }

    /**
     * Unstages exactly `paths` (absolute) back to HEAD's own version —
     * the worktree itself is untouched, same as VS Code's own "Unstage
     * Changes". Not plain `git restore --staged` throughout: that
     * fails outright ("fatal: could not resolve HEAD") in a repository
     * with no commits yet at all — every staged path there is
     * necessarily newly added anyway, so `git rm --cached` drops it
     * from the index with the same result, HEAD or not.
     */
    public static void unstage (string root_path, string[] paths) throws CommandError {
      if (has_head (root_path)) {
        Command.run_on_paths (root_path, { "restore", "--staged", "--" }, paths);
        return;
      }
      Command.run_on_paths (root_path, { "rm", "--cached", "--ignore-unmatch", "--" }, paths);
    }

    public static async void add_async (string root_path, string[] paths) throws CommandError {
      yield Command.in_thread (() => add (root_path, paths));
    }

    /** Whole on the background thread, has_head()'s own extra subprocess included. */
    public static async void unstage_async (string root_path, string[] paths) throws CommandError {
      yield Command.in_thread (() => unstage (root_path, paths));
    }

    private static bool has_head (string root_path) {
      if (!HostCommand.has_program ("git")) {
        return false;
      }
      string[] argv = HostCommand.argv ({ "git", "-C", root_path, "rev-parse", "--verify", "-q", "HEAD" });

      var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_SILENCE);
      Subprocess process;
      try {
        process = launcher.spawnv (argv);
        process.wait ();
      } catch (Error e) {
        return false;
      }
      return process.get_successful ();
    }
  }
}
