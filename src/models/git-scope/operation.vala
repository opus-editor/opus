/**
 * Finishing or dropping what GitScope.WorkingTree.operation reports:
 * the commit itself, and `git <op> --continue`/`--abort` for an
 * operation parked on a conflict. A plain `git commit` closes a merge
 * (git sees MERGE_HEAD and makes the two-parent commit itself) but not
 * a rebase, cherry-pick or revert — those stay parked until their own
 * `--continue`, which is why GitView.StagingPane's main button runs
 * resume() rather than commit() for them (VS Code's own "Continue").
 */
namespace GitScope {
  public class Operation : Object {
    /** `git commit -m message` — a plain commit, or the merge commit when a merge is parked. */
    public static void commit (string root_path, string message) throws CommandError {
      Command.run (root_path, { "commit", "-m", message });
    }

    /**
     * `git <op> --continue` with `message` as the stopped commit's own
     * message: written first to the file the sequencer reads back —
     * MERGE_MSG for a cherry-pick/revert, `rebase-merge/message` for a
     * rebase (both, to be safe) — and `core.editor=true` so git takes it
     * without opening an editor of its own. Nothing happens for NONE or
     * MERGE — see commit().
     */
    public static void resume (string root_path, OperationKind kind, string message) throws CommandError {
      if (kind == OperationKind.NONE || kind == OperationKind.MERGE) {
        return;
      }
      write_message (root_path, message);
      Command.run (root_path, { "-c", "core.editor=true", kind.subcommand (), "--continue" });
    }

    /** `git <op> --abort`: back to before the operation started, everything resolved so far included. Nothing happens for NONE. */
    public static void abort (string root_path, OperationKind kind) throws CommandError {
      if (kind == OperationKind.NONE) {
        return;
      }
      Command.run (root_path, { kind.subcommand (), "--abort" });
    }

    public static async void commit_async (string root_path, string message) throws CommandError {
      yield Command.in_thread (() => commit (root_path, message));
    }

    public static async void resume_async (string root_path, OperationKind kind, string message) throws CommandError {
      yield Command.in_thread (() => resume (root_path, kind, message));
    }

    public static async void abort_async (string root_path, OperationKind kind) throws CommandError {
      yield Command.in_thread (() => abort (root_path, kind));
    }

    private static void write_message (string root_path, string message) throws CommandError {
      var git_dir = Command.git_dir (root_path);
      if (git_dir == null) {
        throw new CommandError.NOT_AVAILABLE ("Git isn’t installed, or isn’t on this computer’s PATH.");
      }
      string[] targets = { Path.build_filename (git_dir, "MERGE_MSG") };
      var rebase_message = Path.build_filename (git_dir, "rebase-merge", "message");
      if (FileUtils.test (Path.get_dirname (rebase_message), FileTest.IS_DIR)) {
        targets += rebase_message;
      }
      foreach (var target in targets) {
        try {
          FileUtils.set_contents (target, message);
        } catch (Error e) {
          throw new CommandError.FAILED (e.message);
        }
      }
    }
  }
}
