/**
 * Settling a conflicted path (GitScope.WorkingTree.conflicts) without
 * opening it: take one whole side, keep or drop a file one side
 * deleted, or stage it as it is — VS Code's own per-resource merge
 * actions ("Accept Current/Incoming", "Keep Our/Their Version",
 * "Delete File", extensions/git/src/commands.ts). `git checkout
 * --ours/--theirs` only writes the worktree, so each is followed by
 * `git add`: that is what collapses the index's three stages into one
 * and takes the path out of the conflict.
 */
namespace GitScope {
  public class Resolve : Object {
    /** The HEAD side (`<<<<<<< HEAD` block) for every path, staged — "Accept Current". */
    public static void accept_ours (string root_path, string[] paths) throws CommandError {
      Command.run_on_paths (root_path, { "checkout", "--ours", "--" }, paths);
      Command.run_on_paths (root_path, { "add", "--" }, paths);
    }

    /** The other side (`>>>>>>>` block) for every path, staged — "Accept Incoming". */
    public static void accept_theirs (string root_path, string[] paths) throws CommandError {
      Command.run_on_paths (root_path, { "checkout", "--theirs", "--" }, paths);
      Command.run_on_paths (root_path, { "add", "--" }, paths);
    }

    /** Stages the paths as they are on disk — "Keep … Version", or staging a file whose markers were resolved by hand (or knowingly left in). */
    public static void keep (string root_path, string[] paths) throws CommandError {
      Command.run_on_paths (root_path, { "add", "--" }, paths);
    }

    /** Removes the paths from disk and index — "Delete File" on a path one side deleted. */
    public static void remove (string root_path, string[] paths) throws CommandError {
      Command.run_on_paths (root_path, { "rm", "--" }, paths);
    }

    /** Whether the file still carries git's conflict markers — VS Code's own regex (`^<{7}\s|^={7}$|^>{7}\s`), what decides if staging it deserves a warning first. False for a file that can't be read. */
    public static bool has_conflict_markers (string path) {
      string contents;
      try {
        FileUtils.get_contents (path, out contents);
      } catch (Error e) {
        return false;
      }
      foreach (var raw_line in contents.split ("\n")) {
        var line = raw_line.has_suffix ("\r") ? raw_line.substring (0, raw_line.length - 1) : raw_line;
        if (line.has_prefix ("<<<<<<< ") || line == "=======" || line.has_prefix (">>>>>>> ")) {
          return true;
        }
      }
      return false;
    }

    public static async void accept_ours_async (string root_path, string[] paths) throws CommandError {
      yield Command.in_thread (() => accept_ours (root_path, paths));
    }

    public static async void accept_theirs_async (string root_path, string[] paths) throws CommandError {
      yield Command.in_thread (() => accept_theirs (root_path, paths));
    }

    public static async void keep_async (string root_path, string[] paths) throws CommandError {
      yield Command.in_thread (() => keep (root_path, paths));
    }

    public static async void remove_async (string root_path, string[] paths) throws CommandError {
      yield Command.in_thread (() => remove (root_path, paths));
    }
  }
}
