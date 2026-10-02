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
    '../src/views/main/command-bar/index.blp',
    '../src/views/main/command-bar/_row.blp',
  ),
  output: '.',
  command: [
    blueprint_compiler, 'batch-compile',
    '@OUTDIR@', views_dir, '@INPUT@',
  ],
)

opus_resources = gnome.compile_resources(
  'opus-resources',
  'io.github.opus_editor.Opus.gresource.xml',
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

# A copy under its installed name, so the `desktop-file` test below
# validates the real thing (the validator rejects a `.in` extension).
desktop_file = configure_file(
  input: 'io.github.opus_editor.Opus.desktop.in',
  output: app_id + '.desktop',
  copy: true,
  install: true,
  install_dir: get_option('datadir') / 'applications',
)

# AppStream metadata — what GNOME Software (and, later, Flathub) show
# for the app: name, description, releases. Validated by the
# `metainfo` test below, so a stale release list or a summary past
# AppStream's own limits fails `meson test` instead of a store review.
metainfo_file = 'io.github.opus_editor.Opus.metainfo.xml'
install_data(
  metainfo_file,
  install_dir: get_option('datadir') / 'metainfo',
)

appstreamcli = find_program('appstreamcli', required: false)
if appstreamcli.found()
  test('metainfo', appstreamcli,
    args: ['validate', '--no-net', '--pedantic', files(metainfo_file)],
  )
endif

desktop_file_validate = find_program('desktop-file-validate', required: false)
if desktop_file_validate.found()
  test('desktop-file', desktop_file_validate, args: [desktop_file])
endif

install_data(
  'io.github.opus_editor.Opus.gschema.xml',
  install_dir: get_option('datadir') / 'glib-2.0' / 'schemas',
)

# The app icon the launcher and the shell show — looked up by app id in
# the hicolor theme, so the file name is the app id (the desktop file's
# own Icon= line). The icons under icons/scalable/actions and
# icons/symbols are a different thing: resources compiled into the
# binary above, never installed.
install_data(
  'icons/hicolor/scalable/apps/io.github.opus_editor.Opus.svg',
  install_dir: get_option('datadir') / 'icons' / 'hicolor' / 'scalable' / 'apps',
)

# Compiles every *.gschema.xml in this directory into
# meson.current_build_dir()/gschemas.compiled — `build_by_default: true`
# means a plain `ninja` already produces it, no `ninja install` needed, so
# GLib.Settings works for an uninstalled `just run` too (see the justfile's
# own GSETTINGS_SCHEMA_DIR, pointed at this same build dir).
gnome.compile_schemas(build_by_default: true)
