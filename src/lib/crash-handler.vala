/**
 * A SIGSEGV/SIGABRT/… handler that saves a real backtrace to a file
 * instead of a crash's only trace being whatever scrolled past in a
 * terminal that's since been closed. Nothing in this class is itself
 * debug-only — install() is a plain function like any other — main.vala
 * is the one that only ever calls it inside its own `#if DEBUG` block,
 * same as Opus.Dev.DevServer is only ever constructed inside App.vala's.
 */
namespace CrashHandler {
  // SIGABRT covers GLib's own fatal-error path (g_error()/a failed
  // g_assert()/g_return_if_fail()), not just a literal memory-safety
  // segfault — both are exactly the kind of crash this exists for.
  private const int[] CAUGHT_SIGNALS = {
    (int) Posix.Signal.SEGV, (int) Posix.Signal.ABRT, (int) Posix.Signal.BUS, (int) Posix.Signal.ILL, (int) Posix.Signal.FPE
  };

  /**
   * Installs the same handler for every signal in CAUGHT_SIGNALS. Call
   * once, as early as possible in main() — before Adw/Gtk even
   * initializes, so a crash during startup is covered too.
   *
   * The handler shells out to `gdb -p <this process>`, still alive and
   * simply blocked inside the handler itself, to pull a real
   * symbolized backtrace (function names, source files/lines — this
   * project's own debug buildtype already compiles with -g) rather
   * than hand-rolling one from raw `backtrace()`/`backtrace_symbols_fd()`
   * addresses, which would need a second, offline symbolization pass
   * to be useful at all.
   *
   * `Posix.system()` isn't itself async-signal-safe, and neither is
   * gdb's own PTRACE_ATTACH against a process it didn't fork — both
   * accepted here: this is a developer debugging aid, not a hardened
   * crash reporter, and it works in the overwhelming majority of real
   * crashes. On a system with Yama's ptrace_scope raised above its
   * default 0 (stock Ubuntu ships at 1), gdb attaching to its own
   * *parent* like this would also need `prctl(PR_SET_PTRACER, …)`
   * called here first — not added, since checked directly and this
   * project's own dev machine already runs at ptrace_scope 0.
   *
   * Re-raises the same signal with its default disposition restored
   * once gdb detaches, rather than exiting some other way — the
   * process still crashes exactly as it would have otherwise (its own
   * exit code, a real core dump too if the system's ulimit/core_pattern
   * allow one), this only adds the backtrace file alongside that.
   */
  public static void install () {
    foreach (var signum in CAUGHT_SIGNALS) {
      Posix.signal (signum, handle_crash);
    }
  }

  private static void handle_crash (int signum) {
    var log_path = crash_log_path ();
    DirUtils.create_with_parents (Path.get_dirname (log_path), 0755);

    stderr.printf ("Opus crashed (%s) — writing a backtrace to %s\n", Posix.strsignal (signum) ?? signum.to_string (), log_path);

    var command = "gdb -p %d -batch -ex 'set pagination off' -ex 'thread apply all bt full' -ex detach -ex quit > %s 2>&1".printf (
      (int) Posix.getpid (), Shell.quote (log_path)
    );
    Posix.system (command);

    // Restores the crash's own default fate (terminate, core dump if
    // the system allows one) instead of this handler silently
    // swallowing it — a signal handler installed via Posix.signal()
    // doesn't return to whatever the crash actually interrupted here.
    Posix.signal (signum, Posix.SIG_DFL);
    Posix.raise (signum);
  }

  private static string crash_log_path () {
    var timestamp = new DateTime.now_local ().format ("%Y%m%d-%H%M%S");
    return Path.build_filename (Environment.get_user_cache_dir (), "opus", "crashes", "crash-%s.log".printf (timestamp));
  }
}
