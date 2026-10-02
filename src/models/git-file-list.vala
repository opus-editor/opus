/**
 * Every file under a git repository that git itself doesn't ignore:
 * `git ls-files --cached --others --exclude-standard` — every tracked
 * file, plus every untracked one not hidden by a `.gitignore`,
 * `.git/info/exclude`, or the user's own global `core.excludesFile`
 * (`--exclude-standard` covers all three at once, more than a
 * `.gitignore`-only parser would). A real git subprocess, not a
 * hand-rolled pattern matcher: VS Code's own search hands the same job
 * to ripgrep's native gitignore support, and its pure-JS `IgnoreFile`
 * only exists because that path also runs in a browser tab with no way
 * to spawn `git` — a constraint this native app doesn't have.
 *
 * Git's list is the index's view, not the disk's: a tracked file deleted
 * from the worktree is still listed, a symlink is listed as a file, a
 * submodule as one entry. One `lstat` per path keeps only what is a real
 * regular file right now — the same set a {@link Opus.FuzzyFinder.DirectoryWalker}
 * over the same tree would report, minus the ignored ones. Cheaper than
 * the walker's own per-entry checks, so the gitignore path is never the
 * slow one.
 *
 * Two ways to consume the same listing: as an `Opus.FuzzyFinder.IPathSource`
 * (`start()`, stdout read line by line on its own thread and streamed
 * in batches, for the Command Bar) or all at once (`list_sync()`, for
 * Find in Files' own synchronous walk).
 *
 * Plain newline-separated output, not `-z`/NUL-separated: Vala has no
 * way to spell a literal NUL as a split delimiter (a `"\0"` literal is
 * already an empty C string by then), and the codebase assumes `\n` as
 * the line separator everywhere else anyway. `-c core.quotePath=false`
 * stops git from octal-escaping non-ASCII bytes in that output; a path
 * containing a literal `"` or `\` is still always escaped and never
 * unescaped here — the same accepted limitation GitStatus documents.
 */
public class GitFileList : Object, Opus.FuzzyFinder.IPathSource {
  public uint batch_size { get; set; default = 256; }

  private string root_path;
  private bool started = false;

  /**
   * Git couldn't answer at all — not on PATH, `root_path` not inside a
   * repository, or some other git-level failure. Emitted on the main
   * loop *instead of* finished(): the caller's own fallback (list
   * everything, ignoring nothing) is what "no real answer available"
   * means.
   */
  public signal void failed ();

  public GitFileList (string root_path) {
    this.root_path = root_path;
  }

  /**
   * Whether `root_path` is itself the top of a repository (a `.git`
   * directory, or a worktree's `.git` file) — a zero-subprocess
   * pre-check so a plain folder never pays for a `git` spawn that would
   * only fail. A folder *inside* a repository fails this check and just
   * gets the unfiltered listing; failed() still covers git itself being
   * missing or broken.
   */
  public static bool is_repository_root (string root_path) {
    return FileUtils.test (Path.build_filename (root_path, ".git"), FileTest.EXISTS);
  }

  public void start (Cancellable cancellable) {
    if (started) {
      return;
    }
    started = true;

    var size = batch_size;
    new Thread<void> ("git-file-list", () => {
      var pending = new GenericArray<string> ();
      bool answered = read_paths (root_path, cancellable, (relative_path) => {
        pending.add (relative_path);
        if (pending.length >= size) {
          emit_batch (pending);
          pending.remove_range (0, pending.length);
        }
      });

      if (cancellable.is_cancelled ()) {
        emit_on_main_loop (() => finished (true));
        return;
      }
      if (!answered) {
        emit_on_main_loop (() => failed ());
        return;
      }
      if (pending.length > 0) {
        emit_batch (pending);
      }
      emit_on_main_loop (() => finished (false));
    });
  }

  /** The whole listing at once, root-relative, in git's own sorted order — null whenever git can't answer (see failed()). */
  public static string[]? list_sync (string root_path) {
    string[] paths = {};
    bool answered = read_paths (root_path, null, (relative_path) => {
      paths += relative_path;
    });
    return answered ? paths : null;
  }

  private delegate void PathSink (string relative_path);

  /** Hands every listed path that is a regular file right now to `on_path`, as git prints them. Returns false when git couldn't answer at all. */
  private static bool read_paths (string root_path, Cancellable? cancellable, PathSink on_path) {
    if (!HostCommand.has_program ("git")) {
      return false;
    }

    var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_SILENCE);
    string[] argv = HostCommand.argv ({
      "git", "-c", "core.quotePath=false", "-C", root_path,
      "ls-files", "--cached", "--others", "--exclude-standard",
    });

    Subprocess process;
    try {
      process = launcher.spawnv (argv);
    } catch (Error e) {
      return false;
    }

    var stdout_stream = new DataInputStream (process.get_stdout_pipe ());
    try {
      string? line;
      while ((line = stdout_stream.read_line (null, cancellable)) != null) {
        if (line != "" && line.validate () && is_regular_file (Path.build_filename (root_path, line))) {
          on_path (line);
        }
      }
    } catch (Error e) {
      process.force_exit (); // cancelled mid-stream — git has nothing left to tell us
    }

    try {
      process.wait ();
    } catch (Error e) {
      return false;
    }
    return process.get_successful ();
  }

  /** A single lstat: true only for a regular file — never a symlink (even one to a regular file), a directory, or a path that is gone from disk. */
  private static bool is_regular_file (string path) {
    Posix.Stat info;
    if (Posix.lstat (path, out info) != 0) {
      return false;
    }
    return Posix.S_ISREG (info.st_mode);
  }

  private void emit_batch (GenericArray<string> pending) {
    var paths = new string[pending.length];
    for (uint i = 0; i < pending.length; i++) {
      paths[i] = pending[i];
    }
    emit_on_main_loop (() => batch (paths));
  }

  private delegate void Emission ();

  private void emit_on_main_loop (owned Emission emit) {
    Idle.add (() => {
      emit ();
      return Source.REMOVE;
    });
  }
}
