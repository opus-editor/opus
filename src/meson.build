codi_model_sources = files(
  'models/file-node.vala',
  'models/file-tree.vala',
)

codi_sources = [
  files('main.vala'),
  codi_model_sources,
]

executable(
  'codi-gtk',
  codi_sources,
  codi_resources,
  dependencies: [glib_dep, gobject_dep, gio_dep, gtk_dep, adwaita_dep],
  install: true,
)
