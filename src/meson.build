opus_model_sources = files(
  'models/document.vala',
  'models/file-node.vala',
  'models/file-tree.vala',
  'models/logger.vala',
  'models/workspace.vala',
)

opus_gtk_view_sources = files(
  'views/file-tree/_row.vala',
  'views/file-tree/index.vala',
  'views/tab-bar/_pill.vala',
  'views/tab-bar/index.vala',
  'views/editor/index.vala',
  'views/main-window/index.vala',
)

opus_controller_sources = files(
  'controllers/file-tree-controller.vala',
  'controllers/editor-controller.vala',
  'controllers/main-controller.vala',
)

opus_sources = files(
  'main.vala',
) + opus_model_sources + opus_gtk_view_sources + opus_controller_sources

executable(
  'opus',
  opus_sources,
  opus_resources,
  dependencies: [glib_dep, gobject_dep, gio_dep, gtk_dep, adwaita_dep],
  install: true,
)
