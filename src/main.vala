/**
 * The app id itself is overridable via OPUS_APP_ID — unset for every real
 * launch (the normal "io.github.nowaos.Opus" applies), set by
 * SystemTestSession to a value unique to that one test run. Without this,
 * a system test's own freshly-spawned process would find
 * "io.github.nowaos.Opus" already owned by any real Opus window the
 * developer happens to have open, and GApplication's own single-instance
 * behavior would silently hand the whole test off to *that* window
 * instead of the isolated one just spawned for it.
 */
int main (string[] args) {
  var app_id = Environment.get_variable ("OPUS_APP_ID") ?? "io.github.nowaos.Opus";

  return new App (app_id).run (args);
}
