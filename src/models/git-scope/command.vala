namespace GitScope {
  public errordomain CommandError {
    /** No git to run at all — not on PATH, or the process couldn't be started. */
    NOT_AVAILABLE,
    /** git ran and refused: the message is the command line followed by its own stderr, as a log a user can read. */
    FAILED,
  }

  /** One unit of git work for Command.in_thread() — a mutation and whatever it needs around it. */
  public delegate void Step () throws CommandError;

  /**
   * The one way this namespace runs a git command that changes the
   * repository. A failure is an error carrying git's own words — VS
   * Code and Zed both show stderr as is rather than guessing a cause
   * from the exit code, since git's own message ("Unable to create
   * '.git/index.lock': File exists.") is already the best one available.
   */
  public class Command : Object {
    private Command () {}

    /** Runs `git -C root_path <args…>`. */
    public static void run (string root_path, string[] args) throws CommandError {
      if (!HostCommand.has_program ("git")) {
        throw new CommandError.NOT_AVAILABLE ("Git isn’t installed, or isn’t on this computer’s PATH.");
      }

      string[] command = { "git", "-C", root_path };
      foreach (var arg in args) {
        command += arg;
      }

      var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_PIPE);
      string? stderr_text = null;
      Subprocess process;
      try {
        process = launcher.spawnv (HostCommand.argv (command));
        process.communicate_utf8 (null, null, null, out stderr_text);
      } catch (Error e) {
        throw new CommandError.NOT_AVAILABLE (e.message);
      }
      if (process.get_successful ()) {
        return;
      }
      throw new CommandError.FAILED ("$ %s\n%s".printf (string.joinv (" ", command), (stderr_text ?? "").strip ()));
    }

    /** Runs `git -C root_path <prefix…> <paths…>`. Nothing happens, and nothing fails, with an empty `paths`. */
    public static void run_on_paths (string root_path, string[] prefix, string[] paths) throws CommandError {
      if (paths.length == 0) {
        return;
      }
      string[] args = {};
      foreach (var arg in prefix) {
        args += arg;
      }
      foreach (var path in paths) {
        args += path;
      }
      run (root_path, args);
    }

    /** The repository's own `.git` directory (absolute) — a worktree's or submodule's `.git` is a file pointing elsewhere, so never assumed to be `root_path/.git`. Null if git couldn't answer. */
    public static string? git_dir (string root_path) {
      if (!HostCommand.has_program ("git")) {
        return null;
      }
      string[] argv = HostCommand.argv ({ "git", "-C", root_path, "rev-parse", "--absolute-git-dir" });
      var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_SILENCE);
      try {
        var process = launcher.spawnv (argv);
        string stdout_text;
        process.communicate_utf8 (null, null, out stdout_text, null);
        if (!process.get_successful ()) {
          return null;
        }
        return stdout_text.strip ();
      } catch (Error e) {
        return null;
      }
    }

    /** Runs `step` on a background thread and resumes the caller on the main loop with its outcome — Thread + Idle.add, same shape as GitScope.WorkingTree.run_async(). */
    public static async void in_thread (owned Step step) throws CommandError {
      SourceFunc callback = in_thread.callback;
      CommandError? failure = null;

      new Thread<void> ("git-command", () => {
        try {
          step ();
        } catch (CommandError e) {
          failure = e;
        }
        Idle.add ((owned) callback);
      });

      yield;
      if (failure != null) {
        throw failure;
      }
    }
  }
}
