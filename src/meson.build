opus_model_sources = files(
  'models/cursor.vala',
  'models/cursor-collection.vala',
  'models/document.vala',
  'models/edit-history.vala',
  'models/edit-history-entry.vala',
  'models/file-node.vala',
  'models/file-tree.vala',
  'models/icon-theme.vala',
  'models/logger.vala',
  'models/text-edit.vala',
  'models/workspace.vala',
)

opus_gtk_view_sources = files(
  'views/popover-menu.vala',
  'views/drag-drop.vala',
  'views/file-tree/_row.vala',
  'views/file-tree/index.vala',
  'views/tab-bar/_ghost.vala',
  'views/tab-bar/_pill.vala',
  'views/tab-bar/index.vala',
  'views/editor/_colors.vala',
  'views/editor/_drag-payload.vala',
  'views/editor/_source-view.vala',
  'views/editor/index.vala',
  'views/main-window/index.vala',
)

opus_controller_sources = files(
  'controllers/file-tree-controller.vala',
  'controllers/cursor-controller.vala',
  'controllers/editor-controller.vala',
  'controllers/main-controller.vala',
)

# Always compiled, same as models/logger.vala — only ever actually used
# from behind main.vala's own `#if DEBUG`, so it's inert (never
# registered, never reachable) in a release build despite being part of
# the binary. See its own doc comment for what it's for.
opus_module_sources = files(
  'modules/dev-server/index.vala',
)

opus_sources = files(
  'main.vala',
) + opus_model_sources + opus_gtk_view_sources + opus_controller_sources + opus_module_sources

# Captured (not just called for its side effect) so tests/meson.build can
# point SystemTestSession at the real built binary via full_path() — meson
# shares variable scope across subdir()s in call order, same as
# opus_model_sources already being used from tests/meson.build below.
opus_exe = executable(
  'opus',
  opus_sources,
  opus_resources,
  dependencies: [glib_dep, gobject_dep, gio_dep, gtk_dep, adwaita_dep, sourceview_dep, json_glib_dep],
  install: true,
)
