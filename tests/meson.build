trivial_test = executable(
  'trivial-test',
  'trivial-test.vala',
  dependencies: [glib_dep, gobject_dep],
)
test('trivial', trivial_test)

file_tree_test = executable(
  'file-tree-test',
  ['models/file-tree-test.vala', codi_model_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep],
)
test('file-tree', file_tree_test)
