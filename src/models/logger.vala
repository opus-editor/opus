/**
 * Stderr logger gated behind a single verbosity flag, set once at startup
 * from the `-v`/`--verbose` CLI flag. Silent by default so normal runs stay
 * quiet; `just run -v` (or `--verbose`) turns it on.
 *
 * In a release build (`meson setup --buildtype=release`), `DEBUG` isn't
 * defined and every function here compiles to an empty body — calls stay in
 * the source, but the logging itself is stripped from the binary entirely,
 * not just silenced at runtime.
 */
namespace Logger {
#if DEBUG
  private bool verbose_enabled = false;

  public void configure (bool verbose) {
    verbose_enabled = verbose;
  }

  public void info (string message) {
    if (verbose_enabled) {
      stderr.printf ("INFO: %s\n", message);
    }
  }

  public void warn (string message) {
    if (verbose_enabled) {
      stderr.printf ("WARN: %s\n", message);
    }
  }
#else
  public void configure (bool verbose) {
  }

  public void info (string message) {
  }

  public void warn (string message) {
  }
#endif
}
