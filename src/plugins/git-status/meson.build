# Standalone for now: this plugin's own provider.vala/plugin.vala (which
# need libpeas plus the FileDecoration.*/WorkspaceContext contract from
# src/models/, neither built yet — see GIT_STATUS_PLUGIN_PLAN.md) land in a
# later increment. Only the git-agnostic GitStatus model exists so far, so
# this is its own tiny build unit rather than wired into opus_sources.
opus_git_status_plugin_sources = files('git-status.vala')

# Split by concern, not just one binary for the whole plugin: this is a
# plugin package, not a Model (src/models/CLAUDE.md's "one binary per
# Model" doesn't bind it) — run/run_async's own plumbing (no repo, the
# async wrapper) is a different kind of thing to verify than what a real
# repo's various working-tree states classify as.
git_status_run_test = executable(
  'git-status-run-test',
  ['test/git-status-run-test.vala', opus_git_status_plugin_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep],
)
test('git-status-run', git_status_run_test)

git_status_classify_test = executable(
  'git-status-classify-test',
  ['test/git-status-classify-test.vala', opus_git_status_plugin_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep],
)
test('git-status-classify', git_status_classify_test)
