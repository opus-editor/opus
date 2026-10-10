/**
 * Discards unstaged changes — VS Code's own "Discard Changes"/"Discard
 * All Changes" (`git.clean`/`git.cleanAll`, extensions/git/src/
 * commands.ts): a tracked change restores from the index (`git
 * restore`), same source `GitScope.Stage.unstage()` leaves it at; an
 * untracked path has no index entry to restore from, so it's removed
 * from disk instead (`git clean`). Tracked paths go first, and a
 * failure there stops before anything is deleted — surfaced as
 * GitScope.CommandError (see GitScope.Command). A conflicted path is
 * never passed here: it lives in WorkingTree.conflicts, with
 * GitScope.Resolve's own actions instead.
 */
namespace GitScope {
  public class Discard : Object {
    /** Nothing happens with an empty `changes`. */
    public static void run (string root_path, GenericArray<Change> changes) throws CommandError {
      string[] tracked_paths = {};
      string[] untracked_paths = {};
      for (uint i = 0; i < changes.length; i++) {
        if (changes[i].kind == ChangeKind.UNTRACKED) {
          untracked_paths += changes[i].path;
        } else {
          tracked_paths += changes[i].path;
        }
      }

      Command.run_on_paths (root_path, { "restore", "--" }, tracked_paths);
      Command.run_on_paths (root_path, { "clean", "-fd", "--" }, untracked_paths);
    }

    public static async void run_async (string root_path, GenericArray<Change> changes) throws CommandError {
      yield Command.in_thread (() => run (root_path, changes));
    }
  }
}
