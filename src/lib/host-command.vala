/**
 * Runs a command with the user's own tools. A program on this
 * process's PATH is used as is. Inside a Flatpak sandbox the host's
 * `git` (or anything else) isn't visible at all, so a program missing
 * from the sandbox is routed through `flatpak-spawn --host` — the
 * Flatpak portal runs it outside the sandbox and pipes
 * stdin/stdout/stderr back, which needs
 * `--talk-name=org.freedesktop.Flatpak` in the manifest. The same
 * choice VSCodium, Zed and Kate make on Flathub, instead of bundling a
 * second git. "Local first" rather than "sandbox means host": a
 * flatpak-builder build sandbox has `/.flatpak-info` and the Sdk's own
 * git, but no portal — that is where the test suite runs in CI.
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

  private enum Where { NOWHERE, LOCAL, HOST }

  private static HashTable<string, Where>? program_cache = null;

  /** `command` as a launcher should spawn it: untouched when `command[0]` is on this process's PATH, prefixed with `flatpak-spawn --host` when only the host has it. */
  public static string[] argv (string[] command) {
    if (command.length == 0 || where_is (command[0]) != Where.HOST) {
      return command;
    }
    string[] result = { "flatpak-spawn", "--host" };
    foreach (var arg in command) {
      result += arg;
    }
    return result;
  }

  /**
   * Whether `name` can be run at all — here, or on the host through the
   * portal. Answered once per program per process: the portal check is
   * a round-trip, and callers ask on every git call.
   */
  public static bool has_program (string name) {
    return where_is (name) != Where.NOWHERE;
  }

  private static Where where_is (string name) {
    if (program_cache == null) {
      program_cache = new HashTable<string, Where> (str_hash, str_equal);
    }
    if (!program_cache.contains (name)) {
      program_cache[name] = look_up_program (name);
    }
    return program_cache[name];
  }

  /**
   * A directory for files `program` must be able to read: the plain
   * tmp dir when it runs here; when it runs on the host through the
   * portal, the user's cache dir (`~/.var/app/<id>/cache`), which the
   * host sees at the same path, unlike the sandbox's private `/tmp`.
   * Created if missing — the sandbox only guarantees it once the app
   * has run from its own installation.
   */
  public static string shared_tmp_dir (string program) {
    if (where_is (program) != Where.HOST) {
      return Environment.get_tmp_dir ();
    }
    var dir = Environment.get_user_cache_dir ();
    DirUtils.create_with_parents (dir, 0700);
    return dir;
  }

  public static bool in_sandbox () {
    return FileUtils.test (FLATPAK_INFO_PATH, FileTest.EXISTS);
  }

  private static Where look_up_program (string name) {
    if (Environment.find_program_in_path (name) != null) {
      return Where.LOCAL;
    }
    if (!in_sandbox ()) {
      return Where.NOWHERE;
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
      return process.get_successful () ? Where.HOST : Where.NOWHERE;
    } catch (Error e) {
      return Where.NOWHERE;
    }
  }
}
