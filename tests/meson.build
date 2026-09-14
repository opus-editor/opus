trivial_test = executable(
  'trivial-test',
  'trivial-test.vala',
  dependencies: [glib_dep, gobject_dep],
)
test('trivial', trivial_test)

document_test = executable(
  'document-test',
  ['models/document-test.vala', codi_model_sources],
  dependencies: [glib_dep, gobject_dep],
)
test('document', document_test)

workspace_test = executable(
  'workspace-test',
  ['models/workspace-test.vala', codi_model_sources],
  dependencies: [glib_dep, gobject_dep],
)
test('workspace', workspace_test)
