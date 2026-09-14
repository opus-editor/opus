trivial_test = executable(
  'trivial-test',
  'trivial-test.vala',
  dependencies: [glib_dep, gobject_dep],
)
test('trivial', trivial_test)

workspace_test = executable(
  'workspace-test',
  [
    'models/workspace-test.vala',
    meson.project_source_root() / 'src' / 'models' / 'workspace.vala',
  ],
  dependencies: [glib_dep, gobject_dep],
)
test('workspace', workspace_test)
