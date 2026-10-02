# Every model test below built against opus_model_sources on its own —
# but Logger lives in lib/ now (src/lib/CLAUDE.md), and plenty of models
# (UserSettings, …) call Logger.warn()/info() directly, so it needs to
# come along too. opus_logger_sources specifically (see its own comment,
# src/meson.build), not the rest of opus_lib_sources — that needs Gtk,
# these plain model tests have no reason to link.
opus_model_test_sources = opus_model_sources + opus_logger_sources + opus_host_command_sources + opus_fuzzy_finder_sources

command_bar_picker_test = executable(
  'command-bar-picker-test',
  ['models/command-bar-picker-test.vala', opus_model_test_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep, json_glib_dep],
)
test('command-bar-picker', command_bar_picker_test)

command_bar_registry_test = executable(
  'command-bar-registry-test',
  ['models/command-bar-registry-test.vala', opus_model_test_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep, json_glib_dep],
)
test('command-bar-registry', command_bar_registry_test)

command_bar_router_test = executable(
  'command-bar-router-test',
  ['models/command-bar-router-test.vala', opus_model_test_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep, json_glib_dep],
)
test('command-bar-router', command_bar_router_test)

command_bar_recent_files_test = executable(
  'command-bar-recent-files-test',
  ['models/command-bar-recent-files-test.vala', opus_model_test_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep, json_glib_dep],
)
test('command-bar-recent-files', command_bar_recent_files_test)

command_bar_file_provider_test = executable(
  'command-bar-file-provider-test',
  ['models/command-bar-file-provider-test.vala', opus_model_test_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep, json_glib_dep],
)
test('command-bar-file-provider', command_bar_file_provider_test)

command_bar_go_to_line_provider_test = executable(
  'command-bar-go-to-line-provider-test',
  ['models/command-bar-go-to-line-provider-test.vala', opus_model_test_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep, json_glib_dep],
)
test('command-bar-go-to-line-provider', command_bar_go_to_line_provider_test)

document_test = executable(
  'document-test',
  ['models/document-test.vala', opus_model_test_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep, json_glib_dep],
)
test('document', document_test)

editor_config_test = executable(
  'editor-config-test',
  ['models/editor-config-test.vala', opus_model_test_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep, json_glib_dep],
)
test('editor-config', editor_config_test)

display_rows_test = executable(
  'display-rows-test',
  ['models/display-rows-test.vala', opus_model_test_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep, json_glib_dep],
)
test('display-rows', display_rows_test)

indent_guides_test = executable(
  'indent-guides-test',
  ['models/indent-guides-test.vala', opus_model_test_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep, json_glib_dep],
)
test('indent-guides', indent_guides_test)

workspace_test = executable(
  'workspace-test',
  ['models/workspace-test.vala', opus_model_test_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep, json_glib_dep],
)
test('workspace', workspace_test)

session_test = executable(
  'session-test',
  ['models/session-test.vala', opus_model_test_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep, json_glib_dep],
)
test('session', session_test)

file_tree_test = executable(
  'file-tree-test',
  ['models/file-tree-test.vala', opus_model_test_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep, json_glib_dep],
)
test('file-tree', file_tree_test)

file_decoration_registry_test = executable(
  'file-decoration-registry-test',
  ['models/file-decoration-registry-test.vala', opus_model_test_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep, json_glib_dep],
)
test('file-decoration-registry', file_decoration_registry_test)

git_diff_parse_test = executable(
  'git-diff-parse-test',
  ['models/git-diff-parse-test.vala', opus_model_test_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep, json_glib_dep],
)
test('git-diff-parse', git_diff_parse_test)

git_diff_engine_test = executable(
  'git-diff-engine-test',
  ['models/git-diff-engine-test.vala', opus_model_test_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep, json_glib_dep],
)
test('git-diff-engine', git_diff_engine_test)

git_diff_document_tracker_test = executable(
  'git-diff-document-tracker-test',
  ['models/git-diff-document-tracker-test.vala', opus_model_test_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep, json_glib_dep],
)
test('git-diff-document-tracker', git_diff_document_tracker_test)

git_file_list_test = executable(
  'git-file-list-test',
  ['models/git-file-list-test.vala', opus_model_test_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep, json_glib_dep],
)
test('git-file-list', git_file_list_test)

find_in_files_search_test = executable(
  'find-in-files-search-test',
  ['models/find-in-files-search-test.vala', opus_model_test_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep, json_glib_dep],
)
test('find-in-files-search', find_in_files_search_test)

find_in_files_replace_test = executable(
  'find-in-files-replace-test',
  ['models/find-in-files-replace-test.vala', opus_model_test_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep, json_glib_dep],
)
test('find-in-files-replace', find_in_files_replace_test)

find_in_files_scope_test = executable(
  'find-in-files-scope-test',
  ['models/find-in-files-scope-test.vala', opus_model_test_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep, json_glib_dep],
)
test('find-in-files-scope', find_in_files_scope_test)

cursor_collection_test = executable(
  'cursor-collection-test',
  ['models/cursor-collection-test.vala', opus_model_test_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep, json_glib_dep],
)
test('cursor-collection', cursor_collection_test)

edit_history_test = executable(
  'edit-history-test',
  ['models/edit-history-test.vala', opus_model_test_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep, json_glib_dep],
)
test('edit-history', edit_history_test)

replace_pattern_test = executable(
  'replace-pattern-test',
  ['models/replace-pattern-test.vala', opus_model_test_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep, json_glib_dep],
)
test('replace-pattern', replace_pattern_test)

user_settings_test = executable(
  'user-settings-test',
  ['models/user-settings-test.vala', opus_model_test_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep, json_glib_dep],
)
test('user-settings', user_settings_test)

# Links opus_resources too (unlike every other model test above) —
# IconTheme.symbols()'s own test needs the real compiled GResource
# bundle to actually be present to load the bundled Symbols theme from.
icon_theme_test = executable(
  'icon-theme-test',
  ['models/icon-theme-test.vala', opus_model_test_sources],
  opus_resources,
  dependencies: [glib_dep, gobject_dep, gio_dep, json_glib_dep],
)
test('icon-theme', icon_theme_test)

opus_system_test_sources = files(
  'system-test-session.vala',
  'support/system-test-session-tabs.vala',
  'support/system-test-session-editor-text.vala',
  'support/system-test-session-cursors.vala',
  'support/system-test-session-search.vala',
  'support/system-test-session-command-bar.vala',
)

smoke_test = executable(
  'smoke-test',
  ['support/smoke-test.vala', opus_system_test_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep, gtk_dep],
)
# is_parallel: false — each of these spawns real broadwayd/Opus
# processes; running several at once fought over CPU/process-spawn
# time badly enough to time out during development, so they get their
# own exclusive slot instead of racing model tests or each other.
test(
  'smoke',
  smoke_test,
  env: [
    'OPUS_BINARY_PATH=' + opus_exe.full_path(),
    # Without this, GLib.Settings aborts at startup unable to find
    # io.github.opus_editor.Opus's own schema — see data/meson.build's own
    # gnome.compile_schemas() (what actually produces gschemas.compiled
    # here) and the justfile's identical env var for `just run`.
    'GSETTINGS_SCHEMA_DIR=' + meson.project_build_root() / 'data',
  ],
  timeout: 60,
  is_parallel: false,
)

escape_test = executable(
  'escape-test',
  ['system/cursors/escape-test.vala', opus_system_test_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep, gtk_dep],
)
test(
  'escape',
  escape_test,
  env: [
    'OPUS_BINARY_PATH=' + opus_exe.full_path(),
    # Without this, GLib.Settings aborts at startup unable to find
    # io.github.opus_editor.Opus's own schema — see data/meson.build's own
    # gnome.compile_schemas() (what actually produces gschemas.compiled
    # here) and the justfile's identical env var for `just run`.
    'GSETTINGS_SCHEMA_DIR=' + meson.project_build_root() / 'data',
  ],
  timeout: 60,
  is_parallel: false,
)

undo_redo_test = executable(
  'undo-redo-test',
  ['system/editing/undo-redo-test.vala', opus_system_test_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep, gtk_dep],
)
test(
  'undo-redo',
  undo_redo_test,
  env: [
    'OPUS_BINARY_PATH=' + opus_exe.full_path(),
    # Without this, GLib.Settings aborts at startup unable to find
    # io.github.opus_editor.Opus's own schema — see data/meson.build's own
    # gnome.compile_schemas() (what actually produces gschemas.compiled
    # here) and the justfile's identical env var for `just run`.
    'GSETTINGS_SCHEMA_DIR=' + meson.project_build_root() / 'data',
  ],
  timeout: 60,
  is_parallel: false,
)

cursor_merge_test = executable(
  'cursor-merge-test',
  ['system/cursors/cursor-merge-test.vala', opus_system_test_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep, gtk_dep],
)
test(
  'cursor-merge',
  cursor_merge_test,
  env: [
    'OPUS_BINARY_PATH=' + opus_exe.full_path(),
    # Without this, GLib.Settings aborts at startup unable to find
    # io.github.opus_editor.Opus's own schema — see data/meson.build's own
    # gnome.compile_schemas() (what actually produces gschemas.compiled
    # here) and the justfile's identical env var for `just run`.
    'GSETTINGS_SCHEMA_DIR=' + meson.project_build_root() / 'data',
  ],
  timeout: 60,
  is_parallel: false,
)

word_undo_test = executable(
  'word-undo-test',
  ['system/editing/word-undo-test.vala', opus_system_test_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep, gtk_dep],
)
test(
  'word-undo',
  word_undo_test,
  env: [
    'OPUS_BINARY_PATH=' + opus_exe.full_path(),
    # Without this, GLib.Settings aborts at startup unable to find
    # io.github.opus_editor.Opus's own schema — see data/meson.build's own
    # gnome.compile_schemas() (what actually produces gschemas.compiled
    # here) and the justfile's identical env var for `just run`.
    'GSETTINGS_SCHEMA_DIR=' + meson.project_build_root() / 'data',
  ],
  timeout: 60,
  is_parallel: false,
)

word_jump_test = executable(
  'word-jump-test',
  ['system/cursors/word-jump-test.vala', opus_system_test_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep, gtk_dep],
)
test(
  'word-jump',
  word_jump_test,
  env: [
    'OPUS_BINARY_PATH=' + opus_exe.full_path(),
    # Without this, GLib.Settings aborts at startup unable to find
    # io.github.opus_editor.Opus's own schema — see data/meson.build's own
    # gnome.compile_schemas() (what actually produces gschemas.compiled
    # here) and the justfile's identical env var for `just run`.
    'GSETTINGS_SCHEMA_DIR=' + meson.project_build_root() / 'data',
  ],
  timeout: 60,
  is_parallel: false,
)

select_next_match_test = executable(
  'select-next-match-test',
  ['system/cursors/select-next-match-test.vala', opus_system_test_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep, gtk_dep],
)
test(
  'select-next-match',
  select_next_match_test,
  env: [
    'OPUS_BINARY_PATH=' + opus_exe.full_path(),
    # Without this, GLib.Settings aborts at startup unable to find
    # io.github.opus_editor.Opus's own schema — see data/meson.build's own
    # gnome.compile_schemas() (what actually produces gschemas.compiled
    # here) and the justfile's identical env var for `just run`.
    'GSETTINGS_SCHEMA_DIR=' + meson.project_build_root() / 'data',
  ],
  timeout: 60,
  is_parallel: false,
)

select_all_test = executable(
  'select-all-test',
  ['system/cursors/select-all-test.vala', opus_system_test_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep, gtk_dep],
)
test(
  'select-all',
  select_all_test,
  env: [
    'OPUS_BINARY_PATH=' + opus_exe.full_path(),
    # Without this, GLib.Settings aborts at startup unable to find
    # io.github.opus_editor.Opus's own schema — see data/meson.build's own
    # gnome.compile_schemas() (what actually produces gschemas.compiled
    # here) and the justfile's identical env var for `just run`.
    'GSETTINGS_SCHEMA_DIR=' + meson.project_build_root() / 'data',
  ],
  timeout: 60,
  is_parallel: false,
)

close_tab_test = executable(
  'close-tab-test',
  ['system/tabs/close-tab-test.vala', opus_system_test_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep, gtk_dep],
)
test(
  'close-tab',
  close_tab_test,
  env: [
    'OPUS_BINARY_PATH=' + opus_exe.full_path(),
    # Without this, GLib.Settings aborts at startup unable to find
    # io.github.opus_editor.Opus's own schema — see data/meson.build's own
    # gnome.compile_schemas() (what actually produces gschemas.compiled
    # here) and the justfile's identical env var for `just run`.
    'GSETTINGS_SCHEMA_DIR=' + meson.project_build_root() / 'data',
  ],
  timeout: 60,
  is_parallel: false,
)

cut_paste_test = executable(
  'cut-paste-test',
  ['system/editing/cut-paste-test.vala', opus_system_test_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep, gtk_dep],
)
test(
  'cut-paste',
  cut_paste_test,
  env: [
    'OPUS_BINARY_PATH=' + opus_exe.full_path(),
    # Without this, GLib.Settings aborts at startup unable to find
    # io.github.opus_editor.Opus's own schema — see data/meson.build's own
    # gnome.compile_schemas() (what actually produces gschemas.compiled
    # here) and the justfile's identical env var for `just run`.
    'GSETTINGS_SCHEMA_DIR=' + meson.project_build_root() / 'data',
  ],
  timeout: 60,
  is_parallel: false,
)

add_cursor_vertical_test = executable(
  'add-cursor-vertical-test',
  ['system/cursors/add-cursor-vertical-test.vala', opus_system_test_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep, gtk_dep],
)
test(
  'add-cursor-vertical',
  add_cursor_vertical_test,
  env: [
    'OPUS_BINARY_PATH=' + opus_exe.full_path(),
    # Without this, GLib.Settings aborts at startup unable to find
    # io.github.opus_editor.Opus's own schema — see data/meson.build's own
    # gnome.compile_schemas() (what actually produces gschemas.compiled
    # here) and the justfile's identical env var for `just run`.
    'GSETTINGS_SCHEMA_DIR=' + meson.project_build_root() / 'data',
  ],
  timeout: 60,
  is_parallel: false,
)

tab_backspace_test = executable(
  'tab-backspace-test',
  ['system/editing/tab-backspace-test.vala', opus_system_test_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep, gtk_dep],
)
test(
  'tab-backspace',
  tab_backspace_test,
  env: [
    'OPUS_BINARY_PATH=' + opus_exe.full_path(),
    # Without this, GLib.Settings aborts at startup unable to find
    # io.github.opus_editor.Opus's own schema — see data/meson.build's own
    # gnome.compile_schemas() (what actually produces gschemas.compiled
    # here) and the justfile's identical env var for `just run`.
    'GSETTINGS_SCHEMA_DIR=' + meson.project_build_root() / 'data',
  ],
  timeout: 60,
  is_parallel: false,
)

enter_indent_test = executable(
  'enter-indent-test',
  ['system/editing/enter-indent-test.vala', opus_system_test_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep, gtk_dep],
)
test(
  'enter-indent',
  enter_indent_test,
  env: [
    'OPUS_BINARY_PATH=' + opus_exe.full_path(),
    # Without this, GLib.Settings aborts at startup unable to find
    # io.github.opus_editor.Opus's own schema — see data/meson.build's own
    # gnome.compile_schemas() (what actually produces gschemas.compiled
    # here) and the justfile's identical env var for `just run`.
    'GSETTINGS_SCHEMA_DIR=' + meson.project_build_root() / 'data',
  ],
  timeout: 60,
  is_parallel: false,
)

move_lines_test = executable(
  'move-lines-test',
  ['system/editing/move-lines-test.vala', opus_system_test_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep, gtk_dep],
)
test(
  'move-lines',
  move_lines_test,
  env: [
    'OPUS_BINARY_PATH=' + opus_exe.full_path(),
    # Without this, GLib.Settings aborts at startup unable to find
    # io.github.opus_editor.Opus's own schema — see data/meson.build's own
    # gnome.compile_schemas() (what actually produces gschemas.compiled
    # here) and the justfile's identical env var for `just run`.
    'GSETTINGS_SCHEMA_DIR=' + meson.project_build_root() / 'data',
  ],
  timeout: 60,
  is_parallel: false,
)

overtype_test = executable(
  'overtype-test',
  ['system/editing/overtype-test.vala', opus_system_test_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep, gtk_dep],
)
test(
  'overtype',
  overtype_test,
  env: [
    'OPUS_BINARY_PATH=' + opus_exe.full_path(),
    # Without this, GLib.Settings aborts at startup unable to find
    # io.github.opus_editor.Opus's own schema — see data/meson.build's own
    # gnome.compile_schemas() (what actually produces gschemas.compiled
    # here) and the justfile's identical env var for `just run`.
    'GSETTINGS_SCHEMA_DIR=' + meson.project_build_root() / 'data',
  ],
  timeout: 60,
  is_parallel: false,
)

find_wrap_test = executable(
  'find-wrap-test',
  ['system/find/find-wrap-test.vala', opus_system_test_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep, gtk_dep],
)
test(
  'find-wrap',
  find_wrap_test,
  env: [
    'OPUS_BINARY_PATH=' + opus_exe.full_path(),
    # Without this, GLib.Settings aborts at startup unable to find
    # io.github.opus_editor.Opus's own schema — see data/meson.build's own
    # gnome.compile_schemas() (what actually produces gschemas.compiled
    # here) and the justfile's identical env var for `just run`.
    'GSETTINGS_SCHEMA_DIR=' + meson.project_build_root() / 'data',
  ],
  timeout: 60,
  is_parallel: false,
)

find_in_files_tab_test = executable(
  'find-in-files-tab-test',
  ['system/find/find-in-files-tab-test.vala', opus_system_test_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep, gtk_dep],
)
test(
  'find-in-files-tab',
  find_in_files_tab_test,
  env: [
    'OPUS_BINARY_PATH=' + opus_exe.full_path(),
    'GSETTINGS_SCHEMA_DIR=' + meson.project_build_root() / 'data',
  ],
  timeout: 60,
  is_parallel: false,
)

wrapped_movement_test = executable(
  'wrapped-movement-test',
  ['system/cursors/wrapped-movement-test.vala', opus_system_test_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep, gtk_dep],
)
test(
  'wrapped-movement',
  wrapped_movement_test,
  env: [
    'OPUS_BINARY_PATH=' + opus_exe.full_path(),
    # Without this, GLib.Settings aborts at startup unable to find
    # io.github.opus_editor.Opus's own schema — see data/meson.build's own
    # gnome.compile_schemas() (what actually produces gschemas.compiled
    # here) and the justfile's identical env var for `just run`.
    'GSETTINGS_SCHEMA_DIR=' + meson.project_build_root() / 'data',
  ],
  timeout: 60,
  is_parallel: false,
)

wrapped_selection_test = executable(
  'wrapped-selection-test',
  ['system/cursors/wrapped-selection-test.vala', opus_system_test_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep, gtk_dep],
)
test(
  'wrapped-selection',
  wrapped_selection_test,
  env: [
    'OPUS_BINARY_PATH=' + opus_exe.full_path(),
    # Without this, GLib.Settings aborts at startup unable to find
    # io.github.opus_editor.Opus's own schema — see data/meson.build's own
    # gnome.compile_schemas() (what actually produces gschemas.compiled
    # here) and the justfile's identical env var for `just run`.
    'GSETTINGS_SCHEMA_DIR=' + meson.project_build_root() / 'data',
  ],
  timeout: 60,
  is_parallel: false,
)

# src/lib/fuzzy-finder/ tests — built against opus_fuzzy_finder_sources
# alone (no models, no Logger): the engine's whole point is having no
# dependency on the rest of the app, and these binaries are what prove it.
fuzzy_finder_scorer_test = executable(
  'fuzzy-finder-scorer-test',
  ['lib/fuzzy-finder-scorer-test.vala', opus_fuzzy_finder_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep],
)
test('fuzzy-finder-scorer', fuzzy_finder_scorer_test)

fuzzy_finder_index_test = executable(
  'fuzzy-finder-index-test',
  ['lib/fuzzy-finder-index-test.vala', opus_fuzzy_finder_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep],
)
test('fuzzy-finder-index', fuzzy_finder_index_test)

fuzzy_finder_walker_test = executable(
  'fuzzy-finder-walker-test',
  ['lib/fuzzy-finder-walker-test.vala', opus_fuzzy_finder_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep],
)
test('fuzzy-finder-walker', fuzzy_finder_walker_test)

host_command_test = executable(
  'host-command-test',
  ['lib/host-command-test.vala', opus_host_command_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep],
)
test('host-command', host_command_test)

command_bar_open_file_test = executable(
  'command-bar-open-file-test',
  ['system/command-bar/open-file-test.vala', opus_system_test_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep, gtk_dep],
)
test(
  'command-bar-open-file',
  command_bar_open_file_test,
  env: [
    'OPUS_BINARY_PATH=' + opus_exe.full_path(),
    'GSETTINGS_SCHEMA_DIR=' + meson.project_build_root() / 'data',
  ],
  timeout: 60,
  is_parallel: false,
)
