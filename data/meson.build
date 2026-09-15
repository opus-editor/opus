# Each view owns its own index.blp, colocated with its index.vala under
# src/views/<name>/ (a private sub-component's is _name.blp next to its
# _name.vala). The base dir passed to blueprint-compiler is that views/
# directory, so batch-compile mirrors that layout into the compiled .ui
# resources (e.g. src/views/main-window/index.blp -> main-window/index.ui),
# matching the paths in the .gresource.xml below.
views_dir = meson.project_source_root() / 'src' / 'views'

blueprints = custom_target('blueprints',
  input: files(
    '../src/views/file-tree/_row.blp',
    '../src/views/tab-bar/_pill.blp',
    '../src/views/editor/index.blp',
    '../src/views/main-window/index.blp',
  ),
  output: '.',
  command: [
    blueprint_compiler, 'batch-compile',
    '@OUTDIR@', views_dir, '@INPUT@',
  ],
)

codi_resources = gnome.compile_resources(
  'codi-gtk-resources',
  'io.github.alxmagro.Codi.gresource.xml',
  # Compiled .ui files land in the build dir; icons/ (a few app-bundled
  # symbolic icons that don't exist in the system icon theme) ships from the
  # source tree directly — both are listed here since compile_resources
  # searches every source_dir for each file in the .gresource.xml.
  source_dir: [meson.current_build_dir(), meson.current_source_dir()],
  dependencies: blueprints,
)

install_data(
  'io.github.alxmagro.Codi.desktop.in',
  rename: app_id + '.desktop',
  install_dir: get_option('datadir') / 'applications',
)
