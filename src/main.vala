/**
 * The app id itself is overridable via OPUS_APP_ID — unset for every real
 * launch (the normal "io.github.opus_editor.Opus" applies), set by
 * SystemTestSession to a value unique to that one test run. Without this,
 * a system test's own freshly-spawned process would find
 * "io.github.opus_editor.Opus" already owned by any real Opus window the
 * developer happens to have open, and GApplication's own single-instance
 * behavior would silently hand the whole test off to *that* window
 * instead of the isolated one just spawned for it.
 */
int main (string[] args) {
  #if DEBUG
  // Before anything else, including App/Adw/Gtk init, so a crash
  // during startup itself is covered too — see CrashHandler's own doc
  // comment (src/lib/crash-handler.vala).
  CrashHandler.install ();
  #endif

  int exit_status;
  if (App.answers_locally (args, out exit_status)) {
    return exit_status;
  }

  var app_id = Environment.get_variable ("OPUS_APP_ID") ?? "io.github.opus_editor.Opus";

  return new App (app_id).run (args);
}
