project(
  'opus', 'vala', 'c',
  version: '0.1.3',
  meson_version: '>= 1.0',
)

app_id = 'io.github.opus_editor.Opus'
gettext_package = 'opus'

glib_dep = dependency('glib-2.0')
gobject_dep = dependency('gobject-2.0')
gio_dep = dependency('gio-2.0')
gtk_dep = dependency('gtk4')
adwaita_dep = dependency('libadwaita-1')
sourceview_dep = dependency('gtksourceview-5')
# Parses the bundled "Symbols" icon theme's own JSON (see
# src/models/icon-theme.vala) — the one place in this app that reads
# structured data it doesn't own the schema of.
json_glib_dep = dependency('json-glib-1.0')
# The plugin engine (src/lib/plugins/) — see src/plugins/AGENTS.md for why
# libpeas over a hand-rolled registry or a VS-Code-style extension host
# (GIT_STATUS_PLUGIN_PLAN.md's own Recommendation section).
peas_dep = dependency('libpeas-2')
# Language packages (src/models/syntax/) load each grammar's compiled
# library at runtime.
gmodule_dep = dependency('gmodule-2.0')
# Always the pinned subproject, never a system copy: a grammar's ABI
# has to fall in the range this exact runtime accepts, and distributions
# ship older ones.
tree_sitter_dep = declare_dependency(
  dependencies: [
    subproject('tree-sitter').get_variable('tree_sitter_dep'),
    meson.get_compiler('vala').find_library('tree-sitter', dirs: meson.project_source_root() / 'vapi'),
  ],
)

gnome = import('gnome')
i18n = import('i18n')

blueprint_compiler = find_program('blueprint-compiler')

# Debug-only code (Logger.warn/info/debug calls) compiles out entirely in a
# release build — like Vite stripping dev-only code from a prod bundle —
# instead of just being silenced at runtime. See src/lib/logger.vala.
if get_option('buildtype') == 'debug'
  add_project_arguments('--define=DEBUG', language: 'vala')
endif

# CrashHandler (src/lib/crash-handler.vala) is Posix.signal()/
# Posix.system()/etc. — always compiled (main.vala only calls it under
# its own `#if DEBUG`, the class itself isn't conditional), so this
# isn't scoped to the debug buildtype above. posix.vapi ships with
# valac itself, no extra library to actually link (every symbol it
# declares is already in libc).
add_project_arguments('--pkg=posix', language: 'vala')

# All C in this project is Vala-generated GObject boilerplate, never hand-written,
# so these warnings only ever fire on codegen we don't control.
add_project_arguments(
  '-DGETTEXT_PACKAGE="@0@"'.format(gettext_package), # required by glib/gi18n-lib.h, which valac emits for any _() call
  '-DOPUS_VERSION="@0@"'.format(meson.project_version()), # the one source of the version — see src/build-info.vala
  # The install dirs languages/meson.build uses — see src/build-info.vala.
  '-DOPUS_LANGUAGES_DIR="@0@"'.format(get_option('prefix') / get_option('datadir') / 'opus' / 'languages'),
  '-DOPUS_THEMES_DIR="@0@"'.format(get_option('prefix') / get_option('datadir') / 'opus' / 'themes'),
  '-DOPUS_GRAMMARS_DIR="@0@"'.format(get_option('prefix') / get_option('libdir') / 'opus' / 'grammars'),
  '-Wno-discarded-qualifiers', # glib's g_once_init_enter() macro (used by every Vala-generated get_type()) discards volatile
  '-Wno-unused-variable', # valac always emits a *_properties array, even for classes with zero GObject properties
  '-Wno-unused-but-set-variable', # valac's generated array-length bookkeeping (e.g. string.data, array literals) always assigns a shadow _size_ local, even when unused
  '-Wno-unused-function', # valac always emits a *_finish() for a private async method fired with .begin() and no callback, even when nothing ever calls it
  language: 'c',
)

subdir('data')
# The bundled editor themes — see src/models/theme.vala for the format.
install_subdir('themes', install_dir: get_option('datadir') / 'opus')
subdir('languages')
subdir('src')
subdir('po')
subdir('tests')

# Recompiles the system's own GSettings schema cache after `ninja install`
# copies io.github.opus_editor.Opus.gschema.xml into the install prefix — that
# prefix's cache won't otherwise pick up a newly-installed schema on its
# own. Irrelevant to `just run`'s own uninstalled dev loop (see the
# GSETTINGS_SCHEMA_DIR env var in the justfile for that case).
gnome.post_install(
  glib_compile_schemas: true,
  # Same idea for the hicolor icon cache and the desktop database: the
  # newly-installed app icon and .desktop file aren't seen by the shell
  # until each is refreshed.
  gtk_update_icon_cache: true,
  update_desktop_database: true,
)
