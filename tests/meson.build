document_test = executable(
  'document-test',
  ['models/document-test.vala', opus_model_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep, json_glib_dep],
)
test('document', document_test)

workspace_test = executable(
  'workspace-test',
  ['models/workspace-test.vala', opus_model_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep, json_glib_dep],
)
test('workspace', workspace_test)

file_tree_test = executable(
  'file-tree-test',
  ['models/file-tree-test.vala', opus_model_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep, json_glib_dep],
)
test('file-tree', file_tree_test)

cursor_collection_test = executable(
  'cursor-collection-test',
  ['models/cursor-collection-test.vala', opus_model_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep, json_glib_dep],
)
test('cursor-collection', cursor_collection_test)

edit_history_test = executable(
  'edit-history-test',
  ['models/edit-history-test.vala', opus_model_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep, json_glib_dep],
)
test('edit-history', edit_history_test)

replace_pattern_test = executable(
  'replace-pattern-test',
  ['models/replace-pattern-test.vala', opus_model_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep, json_glib_dep],
)
test('replace-pattern', replace_pattern_test)

# Links opus_resources too (unlike every other model test above) —
# IconTheme.symbols()'s own test needs the real compiled GResource
# bundle to actually be present to load the bundled Symbols theme from.
icon_theme_test = executable(
  'icon-theme-test',
  ['models/icon-theme-test.vala', opus_model_sources],
  opus_resources,
  dependencies: [glib_dep, gobject_dep, gio_dep, json_glib_dep],
)
test('icon-theme', icon_theme_test)

opus_system_test_sources = files(
  'system-test-session.vala',
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
    # io.github.nowaos.Opus's own schema — see data/meson.build's own
    # gnome.compile_schemas() (what actually produces gschemas.compiled
    # here) and the justfile's identical env var for `just run`.
    'GSETTINGS_SCHEMA_DIR=' + meson.project_build_root() / 'data',
  ],
  timeout: 60,
  is_parallel: false,
)

escape_test = executable(
  'escape-test',
  ['system/escape-test.vala', opus_system_test_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep, gtk_dep],
)
test(
  'escape',
  escape_test,
  env: [
    'OPUS_BINARY_PATH=' + opus_exe.full_path(),
    # Without this, GLib.Settings aborts at startup unable to find
    # io.github.nowaos.Opus's own schema — see data/meson.build's own
    # gnome.compile_schemas() (what actually produces gschemas.compiled
    # here) and the justfile's identical env var for `just run`.
    'GSETTINGS_SCHEMA_DIR=' + meson.project_build_root() / 'data',
  ],
  timeout: 60,
  is_parallel: false,
)

undo_redo_test = executable(
  'undo-redo-test',
  ['system/undo-redo-test.vala', opus_system_test_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep, gtk_dep],
)
test(
  'undo-redo',
  undo_redo_test,
  env: [
    'OPUS_BINARY_PATH=' + opus_exe.full_path(),
    # Without this, GLib.Settings aborts at startup unable to find
    # io.github.nowaos.Opus's own schema — see data/meson.build's own
    # gnome.compile_schemas() (what actually produces gschemas.compiled
    # here) and the justfile's identical env var for `just run`.
    'GSETTINGS_SCHEMA_DIR=' + meson.project_build_root() / 'data',
  ],
  timeout: 60,
  is_parallel: false,
)

cursor_merge_test = executable(
  'cursor-merge-test',
  ['system/cursor-merge-test.vala', opus_system_test_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep, gtk_dep],
)
test(
  'cursor-merge',
  cursor_merge_test,
  env: [
    'OPUS_BINARY_PATH=' + opus_exe.full_path(),
    # Without this, GLib.Settings aborts at startup unable to find
    # io.github.nowaos.Opus's own schema — see data/meson.build's own
    # gnome.compile_schemas() (what actually produces gschemas.compiled
    # here) and the justfile's identical env var for `just run`.
    'GSETTINGS_SCHEMA_DIR=' + meson.project_build_root() / 'data',
  ],
  timeout: 60,
  is_parallel: false,
)

word_undo_test = executable(
  'word-undo-test',
  ['system/word-undo-test.vala', opus_system_test_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep, gtk_dep],
)
test(
  'word-undo',
  word_undo_test,
  env: [
    'OPUS_BINARY_PATH=' + opus_exe.full_path(),
    # Without this, GLib.Settings aborts at startup unable to find
    # io.github.nowaos.Opus's own schema — see data/meson.build's own
    # gnome.compile_schemas() (what actually produces gschemas.compiled
    # here) and the justfile's identical env var for `just run`.
    'GSETTINGS_SCHEMA_DIR=' + meson.project_build_root() / 'data',
  ],
  timeout: 60,
  is_parallel: false,
)

word_jump_test = executable(
  'word-jump-test',
  ['system/word-jump-test.vala', opus_system_test_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep, gtk_dep],
)
test(
  'word-jump',
  word_jump_test,
  env: [
    'OPUS_BINARY_PATH=' + opus_exe.full_path(),
    # Without this, GLib.Settings aborts at startup unable to find
    # io.github.nowaos.Opus's own schema — see data/meson.build's own
    # gnome.compile_schemas() (what actually produces gschemas.compiled
    # here) and the justfile's identical env var for `just run`.
    'GSETTINGS_SCHEMA_DIR=' + meson.project_build_root() / 'data',
  ],
  timeout: 60,
  is_parallel: false,
)

select_next_match_test = executable(
  'select-next-match-test',
  ['system/select-next-match-test.vala', opus_system_test_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep, gtk_dep],
)
test(
  'select-next-match',
  select_next_match_test,
  env: [
    'OPUS_BINARY_PATH=' + opus_exe.full_path(),
    # Without this, GLib.Settings aborts at startup unable to find
    # io.github.nowaos.Opus's own schema — see data/meson.build's own
    # gnome.compile_schemas() (what actually produces gschemas.compiled
    # here) and the justfile's identical env var for `just run`.
    'GSETTINGS_SCHEMA_DIR=' + meson.project_build_root() / 'data',
  ],
  timeout: 60,
  is_parallel: false,
)

select_all_test = executable(
  'select-all-test',
  ['system/select-all-test.vala', opus_system_test_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep, gtk_dep],
)
test(
  'select-all',
  select_all_test,
  env: [
    'OPUS_BINARY_PATH=' + opus_exe.full_path(),
    # Without this, GLib.Settings aborts at startup unable to find
    # io.github.nowaos.Opus's own schema — see data/meson.build's own
    # gnome.compile_schemas() (what actually produces gschemas.compiled
    # here) and the justfile's identical env var for `just run`.
    'GSETTINGS_SCHEMA_DIR=' + meson.project_build_root() / 'data',
  ],
  timeout: 60,
  is_parallel: false,
)

close_tab_test = executable(
  'close-tab-test',
  ['system/close-tab-test.vala', opus_system_test_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep, gtk_dep],
)
test(
  'close-tab',
  close_tab_test,
  env: [
    'OPUS_BINARY_PATH=' + opus_exe.full_path(),
    # Without this, GLib.Settings aborts at startup unable to find
    # io.github.nowaos.Opus's own schema — see data/meson.build's own
    # gnome.compile_schemas() (what actually produces gschemas.compiled
    # here) and the justfile's identical env var for `just run`.
    'GSETTINGS_SCHEMA_DIR=' + meson.project_build_root() / 'data',
  ],
  timeout: 60,
  is_parallel: false,
)

cut_paste_test = executable(
  'cut-paste-test',
  ['system/cut-paste-test.vala', opus_system_test_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep, gtk_dep],
)
test(
  'cut-paste',
  cut_paste_test,
  env: [
    'OPUS_BINARY_PATH=' + opus_exe.full_path(),
    # Without this, GLib.Settings aborts at startup unable to find
    # io.github.nowaos.Opus's own schema — see data/meson.build's own
    # gnome.compile_schemas() (what actually produces gschemas.compiled
    # here) and the justfile's identical env var for `just run`.
    'GSETTINGS_SCHEMA_DIR=' + meson.project_build_root() / 'data',
  ],
  timeout: 60,
  is_parallel: false,
)

add_cursor_vertical_test = executable(
  'add-cursor-vertical-test',
  ['system/add-cursor-vertical-test.vala', opus_system_test_sources],
  dependencies: [glib_dep, gobject_dep, gio_dep, gtk_dep],
)
test(
  'add-cursor-vertical',
  add_cursor_vertical_test,
  env: [
    'OPUS_BINARY_PATH=' + opus_exe.full_path(),
    # Without this, GLib.Settings aborts at startup unable to find
    # io.github.nowaos.Opus's own schema — see data/meson.build's own
    # gnome.compile_schemas() (what actually produces gschemas.compiled
    # here) and the justfile's identical env var for `just run`.
    'GSETTINGS_SCHEMA_DIR=' + meson.project_build_root() / 'data',
  ],
  timeout: 60,
  is_parallel: false,
)
