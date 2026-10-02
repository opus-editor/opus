# Each view owns its own index.blp, colocated with its index.vala under
# src/views/<domain>/<name>/ (a private sub-component's is _name.blp
# next to its _name.vala) — see src/views/CLAUDE.md for the domain
# layout. The base dir passed to blueprint-compiler is the whole views/
# directory, so batch-compile mirrors that layout into the compiled .ui
# resources (e.g. src/views/main/main-window/index.blp ->
# main/main-window/index.ui), matching the paths in the .gresource.xml
# below.
views_dir = meson.project_source_root() / 'src' / 'views'

blueprints = custom_target('blueprints',
  input: files(
    '../src/views/editor-view/explorer-pane/_tree-row.blp',
    '../src/views/editor-view/explorer-pane/index.blp',
    '../src/views/editor-view/editor-pane/tab-bar/_pill.blp',
    '../src/views/editor-view/editor-pane/tab-bar/index.blp',
    '../src/views/editor-view/editor-pane/tab-document/_change-banner.blp',
    '../src/views/editor-view/editor-pane/tab-find-results/index.blp',
    '../src/views/editor-view/find-bar/index.blp',
    '../src/views/editor-view/find-in-files-bar/index.blp',
    '../src/views/components/search-input.blp',
    '../src/views/main/main-window/index.blp',
  ),
  output: '.',
  command: [
    blueprint_compiler, 'batch-compile',
    '@OUTDIR@', views_dir, '@INPUT@',
  ],
)

opus_resources = gnome.compile_resources(
  'opus-resources',
  'io.github.nowaos.Opus.gresource.xml',
  # Compiled .ui files land in the build dir; icons/ (a few app-bundled
  # symbolic icons that don't exist in the system icon theme) ships from
  # the source tree directly; ../src/styles holds the plain .css files
  # every View's own install_css() loads by resource (GlobalCss
  # .install_from_resource()) — Blueprint can't describe a stylesheet
  # itself, only a widget tree, so these are separate files, not part of
  # the blueprints custom_target above. All three are listed here since
  # compile_resources searches every source_dir for each file in the
  # .gresource.xml.
  source_dir: [meson.current_build_dir(), meson.current_source_dir(), meson.project_source_root() / 'src'],
  dependencies: blueprints,
)

install_data(
  'io.github.nowaos.Opus.desktop.in',
  rename: app_id + '.desktop',
  install_dir: get_option('datadir') / 'applications',
)

install_data(
  'io.github.nowaos.Opus.gschema.xml',
  install_dir: get_option('datadir') / 'glib-2.0' / 'schemas',
)

# Compiles every *.gschema.xml in this directory into
# meson.current_build_dir()/gschemas.compiled — `build_by_default: true`
# means a plain `ninja` already produces it, no `ninja install` needed, so
# GLib.Settings works for an uninstalled `just run` too (see the justfile's
# own GSETTINGS_SCHEMA_DIR, pointed at this same build dir).
gnome.compile_schemas(build_by_default: true)
