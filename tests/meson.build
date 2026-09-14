trivial_test = executable(
  'trivial-test',
  'trivial-test.vala',
  dependencies: [glib_dep, gobject_dep],
)
test('trivial', trivial_test)

document_test = executable(
  'document-test',
  'models/document-test.vala',
  document_sources,
  dependencies: [glib_dep, gobject_dep],
)
test('document', document_test)
