trivial_test = executable(
  'trivial-test',
  'trivial-test.vala',
  dependencies: [glib_dep, gobject_dep],
)
test('trivial', trivial_test)

document_test = executable(
  'document-test',
  ['models/document-test.vala', codi_model_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep],
)
test('document', document_test)

workspace_test = executable(
  'workspace-test',
  ['models/workspace-test.vala', codi_model_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep],
)
test('workspace', workspace_test)

file_tree_test = executable(
  'file-tree-test',
  ['models/file-tree-test.vala', codi_model_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep],
)
test('file-tree', file_tree_test)

file_tree_controller_test = executable(
  'file-tree-controller-test',
  [
    'controllers/file-tree-controller-test.vala',
    'fakes/fake-file-tree-view.vala',
    codi_model_sources,
    codi_view_interface_sources,
    codi_controller_sources,
  ],
  dependencies: [glib_dep, gobject_dep, gio_dep],
)
test('file-tree-controller', file_tree_controller_test)

interfaces_compile_test = executable(
  'interfaces-compile-test',
  [
    'interfaces-compile-test.vala',
    'fakes/fake-editor-view.vala',
    'fakes/fake-file-tree-view.vala',
    'fakes/fake-tab-bar-view.vala',
    codi_model_sources,
    codi_view_interface_sources,
  ],
  dependencies: [glib_dep, gobject_dep, gio_dep],
)
test('interfaces-compile', interfaces_compile_test)
