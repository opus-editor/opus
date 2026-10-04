/**
 * What `HEAD` points at, asked of git itself rather than read out of
 * `.git/HEAD`: a linked worktree, a folder below the repository's top
 * level and a reftable repository all answer the same way.
 */
public class GitHead : Object {
  /** Where the repository holding `root_path` keeps its own `HEAD` — a linked worktree's private directory, not the shared one. Null when `root_path` isn't inside a repository. */
  public static string? git_dir (string root_path) {
    return run (root_path, { "rev-parse", "--absolute-git-dir" });
  }

  /** The current branch's name, a short commit when HEAD is detached, null when `root_path` isn't inside a repository. */
  public static string? label (string root_path) {
    // Asked first: unlike rev-parse, it answers on a branch with no commit yet.
    var branch = run (root_path, { "symbolic-ref", "--short", "-q", "HEAD" });
    if (branch != null) {
      return branch;
    }
    return run (root_path, { "rev-parse", "--short", "HEAD" });
  }

  /** Trimmed stdout, or null when git failed or printed nothing. */
  private static string? run (string root_path, string[] args) {
    if (!HostCommand.has_program ("git")) {
      return null;
    }

    string[] command = { "git", "-C", root_path };
    foreach (var arg in args) {
      command += arg;
    }
    var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_SILENCE);

    Subprocess process;
    string? stdout_buf;
    try {
      process = launcher.spawnv (HostCommand.argv (command));
      process.communicate_utf8 (null, null, out stdout_buf, null);
    } catch (Error e) {
      return null;
    }

    if (!process.get_successful () || stdout_buf == null) {
      return null;
    }
    var output = stdout_buf.strip ();
    return output == "" ? null : output;
  }
}
