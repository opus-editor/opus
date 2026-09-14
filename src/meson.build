codi_model_sources = files(
  'models/document.vala',
  'models/file-node.vala',
  'models/file-tree.vala',
  'models/workspace.vala',
)

codi_view_interface_sources = files(
  'views/interfaces/editor-view.vala',
  'views/interfaces/file-tree-view.vala',
  'views/interfaces/tab-bar-view.vala',
)

codi_controller_sources = files(
  'controllers/file-tree-controller.vala',
)

codi_sources = files(
  'main.vala',
) + codi_model_sources + codi_view_interface_sources + codi_controller_sources

executable(
  'codi-gtk',
  codi_sources,
  codi_resources,
  dependencies: [glib_dep, gobject_dep, gio_dep, gtk_dep, adwaita_dep],
  install: true,
)
