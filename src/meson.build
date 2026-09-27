opus_model_sources = files(
  'models/cursor.vala',
  'models/cursor-collection.vala',
  'models/document.vala',
  'models/editor-config.vala',
  'models/edit-history.vala',
  'models/edit-history-entry.vala',
  'models/file-node.vala',
  'models/file-tree.vala',
  'models/icon-theme.vala',
  'models/indent-guides.vala',
  'models/logger.vala',
  'models/replace-pattern.vala',
  'models/selection-snapshot.vala',
  'models/session.vala',
  'models/text-edit.vala',
  'models/user-settings.vala',
  'models/workspace.vala',
)

# Generic, app-domain-independent infrastructure — the "lib/" half of the
# Rails-style app/ vs lib/ split (see src/lib/CLAUDE.md): may need
# Gtk/Adw when the task itself does (GlobalCss loads a real
# Gtk.CssProvider; DevServer drives a real EditorView.EditorPane), but
# neither is an Opus-specific view/widget concept the way everything in
# opus_gtk_view_sources below is.
opus_lib_sources = files(
  'lib/global-css.vala',
  'lib/dev-server/_i-dev-server.vala',
  'lib/dev-server/index.vala',
)

opus_gtk_view_sources = files(
  'views/lib/system-color.vala',
  'views/lib/file-drag/_payload.vala',
  'views/lib/file-drag/_candidate.vala',
  'views/lib/file-drag/index.vala',
  'views/components/context-menu.vala',
  'views/components/search-input.vala',
  'views/main/_i-global-panel.vala',
  'views/main/main-window/index.vala',
  'views/editor-view/editor-pane/text-editor/_cursors.vala',
  'views/editor-view/editor-pane/text-editor/_drag-selection.vala',
  'views/editor-view/editor-pane/text-editor/_search.vala',
  'views/editor-view/editor-pane/text-editor/_source-view.vala',
  'views/editor-view/editor-pane/text-editor/index.vala',
  'views/editor-view/editor-pane/tab-bar/_ghost.vala',
  'views/editor-view/editor-pane/tab-bar/_pill.vala',
  'views/editor-view/editor-pane/tab-bar/index.vala',
  'views/editor-view/editor-pane/_file-watcher.vala',
  'views/editor-view/editor-pane/index.vala',
  'views/editor-view/explorer-pane/_tree-row.vala',
  'views/editor-view/explorer-pane/_tree.vala',
  'views/editor-view/explorer-pane/_inline-edit.vala',
  'views/editor-view/explorer-pane/_dir-watcher.vala',
  'views/editor-view/explorer-pane/_drag-drop.vala',
  'views/editor-view/explorer-pane/index.vala',
  'views/editor-view/find-bar/index.vala',
)

# No opus_controller_sources here — the whole point of this tree: every
# real Controller was absorbed into the View that used to be wired to it
# from outside (EditorController into EditorPane, FileTreeController into
# ExplorerPane, MainController/SearchController into MainWindow,
# CursorController into TextEditorCursors).

opus_sources = files(
  'main.vala',
  'App.vala',
) + opus_model_sources + opus_lib_sources + opus_gtk_view_sources

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
