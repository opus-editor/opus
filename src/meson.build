codi_model_sources = files(
  'models/document.vala',
  'models/file-node.vala',
  'models/file-tree.vala',
  'models/logger.vala',
  'models/workspace.vala',
)

codi_gtk_view_sources = files(
  'views/file-tree/_row.vala',
  'views/file-tree/index.vala',
  'views/tab-bar/_pill.vala',
  'views/tab-bar/index.vala',
  'views/editor/index.vala',
  'views/main-window/index.vala',
)

codi_controller_sources = files(
  'controllers/file-tree-controller.vala',
  'controllers/editor-controller.vala',
  'controllers/main-controller.vala',
)

codi_sources = files(
  'main.vala',
) + codi_model_sources + codi_gtk_view_sources + codi_controller_sources

executable(
  'codi-gtk',
  codi_sources,
  codi_resources,
  dependencies: [glib_dep, gobject_dep, gio_dep, gtk_dep, adwaita_dep],
  install: true,
)
