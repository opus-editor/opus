trivial_test = executable(
  'trivial-test',
  'trivial-test.vala',
  dependencies: [glib_dep, gobject_dep],
)
test('trivial', trivial_test)

document_test = executable(
  'document-test',
  ['models/document-test.vala', opus_model_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep],
)
test('document', document_test)

workspace_test = executable(
  'workspace-test',
  ['models/workspace-test.vala', opus_model_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep],
)
test('workspace', workspace_test)

file_tree_test = executable(
  'file-tree-test',
  ['models/file-tree-test.vala', opus_model_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep],
)
test('file-tree', file_tree_test)
