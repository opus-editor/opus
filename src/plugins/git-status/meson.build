# git-status.vala/provider.vala are plain Model-grade code (no Peas) —
# only plugin.vala touches Peas, so opus_git_status_plugin_sources (used
# by tests that don't want libpeas linked in) stays split from it.
opus_git_status_plugin_sources = files('git-status.vala', 'provider.vala', 'diff-base-provider.vala')
opus_plugin_sources += opus_git_status_plugin_sources + files('plugin.vala')

# git-status.vala alone has no dependency on the shared FileDecoration.*/
# WorkspaceContext contract — kept standalone here (no opus_model_sources)
# so these two stay cheap/fast, same shape as before provider.vala existed.
git_status_run_test = executable(
  'git-status-run-test',
  ['test/git-status-run-test.vala', 'git-status.vala', opus_host_command_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep],
)
test('git-status-run', git_status_run_test)

git_status_classify_test = executable(
  'git-status-classify-test',
  ['test/git-status-classify-test.vala', 'git-status.vala', opus_host_command_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep],
)
test('git-status-classify', git_status_classify_test)

# provider.vala implements FileDecoration.IProvider/IWorkspaceExtension —
# needs the shared model contract (opus_model_sources), but not Peas
# itself (only plugin.vala touches that).
# Links src/meson.build's opus_model_test_dep rather than recompiling
# every model source here — see its comment.
git_status_provider_test = executable(
  'git-status-provider-test',
  ['test/git-status-provider-test.vala', opus_git_status_plugin_sources],
  dependencies: [opus_model_test_dep],
)
test('git-status-provider', git_status_provider_test)

diff_base_provider_test = executable(
  'diff-base-provider-test',
  ['test/diff-base-provider-test.vala', opus_git_status_plugin_sources],
  dependencies: [opus_model_test_dep],
)
test('diff-base-provider', diff_base_provider_test)
