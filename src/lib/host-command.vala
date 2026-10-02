/**
 * Runs a command where the user's own tools live. Natively that is
 * just the process's PATH; inside a Flatpak sandbox the host's `git`
 * (or anything else) isn't visible at all, so the command is routed
 * through `flatpak-spawn --host` — the Flatpak portal runs it outside
 * the sandbox and pipes stdin/stdout/stderr back, which needs
 * `--talk-name=org.freedesktop.Flatpak` in the manifest. The same
 * choice VSCodium, Zed and Kate make on Flathub, instead of bundling a
 * second git.
 *
 * Only the argv changes; every caller still owns its own
 * SubprocessLauncher, flags and output handling. Paths cross the
 * boundary unchanged: the sandbox mounts the user's home at the same
 * path the host has it (`--filesystem=host`) — except the sandbox's
 * private `/tmp`, which the host never sees; see shared_tmp_dir().
 */
public class HostCommand : Object {
  // Flatpak writes this file into every sandbox it starts — the
  // documented way for an app to learn it is running inside one.
  private const string FLATPAK_INFO_PATH = "/.flatpak-info";

  private static HashTable<string, bool>? program_cache = null;

  /** `command` as a launcher should spawn it: untouched natively, prefixed with `flatpak-spawn --host` inside a sandbox. */
  public static string[] argv (string[] command) {
    if (!in_sandbox ()) {
      return command;
    }
    string[] result = { "flatpak-spawn", "--host" };
    foreach (var arg in command) {
      result += arg;
    }
    return result;
  }

  /**
   * Whether `name` is on the PATH the commands above actually run with
   * — Environment.find_program_in_path() would answer for the
   * sandbox's own PATH. Answered once per program per process: the
   * sandboxed check is a portal round-trip, and callers ask on every
   * git call.
   */
  public static bool has_program (string name) {
    if (program_cache == null) {
      program_cache = new HashTable<string, bool> (str_hash, str_equal);
    }
    if (!program_cache.contains (name)) {
      program_cache[name] = look_up_program (name);
    }
    return program_cache[name];
  }

  /**
   * A directory for files a host command must be able to read — the
   * host's own tmp dir natively; inside a sandbox the user's cache dir
   * (`~/.var/app/<id>/cache`), which the host sees at the same path,
   * unlike the sandbox's private `/tmp`.
   */
  public static string shared_tmp_dir () {
    return in_sandbox () ? Environment.get_user_cache_dir () : Environment.get_tmp_dir ();
  }

  public static bool in_sandbox () {
    return FileUtils.test (FLATPAK_INFO_PATH, FileTest.EXISTS);
  }

  private static bool look_up_program (string name) {
    if (!in_sandbox ()) {
      return Environment.find_program_in_path (name) != null;
    }
    // `command -v` through the host's own shell is the portable
    // "is this on PATH" — exit 0 if found, which flatpak-spawn passes
    // through. A missing portal permission fails the same way: no
    // program, nothing to run.
    try {
      var process = new Subprocess (
        SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_SILENCE,
        "flatpak-spawn", "--host", "sh", "-c", "command -v -- \"$1\"", "sh", name
      );
      process.wait ();
      return process.get_successful ();
    } catch (Error e) {
      return false;
    }
  }
}
