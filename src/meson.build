document_sources = files(
  'models/document.vala',
)

codi_sources = files(
  'main.vala',
) + document_sources

executable(
  'codi-gtk',
  codi_sources,
  codi_resources,
  dependencies: [glib_dep, gobject_dep, gio_dep, gtk_dep, adwaita_dep],
  install: true,
)
