opus_model_sources = files(
  'models/cursor.vala',
  'models/cursor-collection.vala',
  'models/document.vala',
  'models/editor-config.vala',
  'models/edit-history.vala',
  'models/edit-history-entry.vala',
  'models/file-decoration/tone.vala',
  'models/file-decoration/state.vala',
  'models/file-decoration/registry.vala',
  'models/file-decoration/i-provider.vala',
  'models/file-node.vala',
  'models/file-tree.vala',
  'models/find-in-files-query.vala',
  'models/find-in-files-match.vala',
  'models/find-in-files-block.vala',
  'models/find-in-files-file-result.vala',
  'models/find-in-files-result.vala',
  'models/find-in-files-search.vala',
  'models/find-in-files-replace.vala',
  'models/find-in-files-replace-result.vala',
  'models/find-in-files-scope.vala',
  'models/git-diff/hunk.vala',
  'models/git-diff/bases.vala',
  'models/git-diff/i-base-provider.vala',
  'models/git-diff/engine.vala',
  'models/git-diff/document-tracker.vala',
  'models/i-display-rows.vala',
  'models/i-workspace-extension.vala',
  'models/icon-theme.vala',
  'models/indent-guides.vala',
  'models/replace-pattern.vala',
  'models/selection-snapshot.vala',
  'models/session.vala',
  'models/text-edit.vala',
  'models/user-settings.vala',
  'models/workspace.vala',
  'models/workspace-context.vala',
)

# Its own variable, not just an entry in opus_lib_sources below: plain
# model tests (tests/meson.build's own opus_model_test_sources,
# git-status/meson.build's own provider/diff-base-provider tests) need
# Logger too — models call Logger.warn()/info() directly (UserSettings,
# …) — but not the rest of opus_lib_sources, which needs Gtk
# (GlobalCss, DevServer) those tests have no reason to link. Declared
# before subdir('plugins') below (git-status/meson.build's own tests
# reference it) rather than where opus_lib_sources itself is declared
# further down. Also not referenced by tests/meson.build via its own
# relative path instead of this shared variable: a file() path written
# from tests/ up into ../src/lib/ resolves to a valac output path that
# escapes that test executable's own private build dir — a `files()`
# reference already resolved from here, src/meson.build's own
# directory, doesn't have that problem (confirmed directly: every model
# test built this way until this same fix).
opus_logger_sources = files('lib/logger.vala')

# After opus_model_sources/opus_logger_sources (git-status-provider-test,
# inside it, links against both) but before opus_sources needs
# opus_plugin_sources below — meson shares variable scope across
# subdir()s in call order.
subdir('plugins')

# Generic, app-domain-independent infrastructure — the "lib/" half of the
# Rails-style app/ vs lib/ split (see src/lib/CLAUDE.md): may need
# Gtk/Adw when the task itself does (GlobalCss loads a real
# Gtk.CssProvider; DevServer drives a real EditorView.EditorPaneWidget), but
# neither is an Opus-specific view/widget concept the way everything in
# opus_gtk_view_sources below is.
opus_lib_sources = opus_logger_sources + files(
  'lib/crash-handler.vala',
  'lib/global-css.vala',
  'lib/dev-server/_i-dev-server.vala',
  'lib/dev-server/index.vala',
  'lib/plugins/engine.vala',
  'lib/plugins/workspace-extensions.vala',
)

opus_gtk_view_sources = files(
  'views/lib/dialogs.vala',
  'views/lib/system-color.vala',
  'views/lib/file-drag/_payload.vala',
  'views/lib/file-drag/_candidate.vala',
  'views/lib/file-drag/index.vala',
  'views/components/context-menu.vala',
  'views/components/search-input.vala',
  'views/components/code-editor/_change-gutter.vala',
  'views/components/code-editor/_clipboard.vala',
  'views/components/code-editor/_cursors.vala',
  'views/components/code-editor/_drag-selection.vala',
  'views/components/code-editor/_input.vala',
  'views/components/code-editor/_search.vala',
  'views/components/code-editor/_selections.vala',
  'views/components/code-editor/_source-view.vala',
  'views/components/code-editor/index.vala',
  'views/main/_i-global-panel.vala',
  'views/main/main-window/index.vala',
  'views/editor-view/editor-pane/tab-bar/_ghost.vala',
  'views/editor-view/editor-pane/tab-bar/_pill.vala',
  'views/editor-view/editor-pane/tab-bar/index.vala',
  'views/editor-view/editor-pane/_i-tab-kind.vala',
  'views/editor-view/editor-pane/tab-document/_change-banner.vala',
  'views/editor-view/editor-pane/tab-document/_file-watcher.vala',
  'views/editor-view/editor-pane/tab-document/index.vala',
  'views/editor-view/editor-pane/tab-find-results/_language-highlighter.vala',
  'views/editor-view/editor-pane/tab-find-results/index.vala',
  'views/editor-view/editor-pane/index.vala',
  'views/editor-view/explorer-pane/_tree-row.vala',
  'views/editor-view/explorer-pane/_tree.vala',
  'views/editor-view/explorer-pane/_inline-edit.vala',
  'views/editor-view/explorer-pane/_dir-watcher.vala',
  'views/editor-view/explorer-pane/_drag-drop.vala',
  'views/editor-view/explorer-pane/index.vala',
  'views/editor-view/find-bar/index.vala',
  'views/editor-view/find-in-files-bar/index.vala',
)

# No opus_controller_sources here — the whole point of this tree: every
# real Controller was absorbed into the View that used to be wired to it
# from outside (EditorController into EditorPaneWidget, FileTreeController into
# ExplorerPane, MainController/SearchController into MainWindow,
# CursorController into CodeEditorCursors).

opus_sources = files(
  'main.vala',
  'App.vala',
) + opus_model_sources + opus_lib_sources + opus_gtk_view_sources + opus_plugin_sources

# Captured (not just called for its side effect) so tests/meson.build can
# point SystemTestSession at the real built binary via full_path() — meson
# shares variable scope across subdir()s in call order, same as
# opus_model_sources already being used from tests/meson.build below.
#
# export_dynamic: true so libpeas's embedded-plugin C loader
# (g_module_open (NULL) against the running executable, then
# g_module_symbol) can actually resolve an embedded plugin's own
# Embedded= entry point — see GIT_STATUS_PLUGIN_PLAN.md's own
# "libpeas 2 is the native answer" section.
opus_exe = executable(
  'opus',
  opus_sources,
  opus_resources,
  dependencies: [glib_dep, gobject_dep, gio_dep, gtk_dep, adwaita_dep, sourceview_dep, json_glib_dep, peas_dep],
  export_dynamic: true,
  install: true,
)
