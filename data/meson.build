blueprints = custom_target('blueprints',
  input: files(
    'ui/file-tree-row.blp',
    'ui/tab-pill.blp',
    'ui/editor-view.blp',
    'ui/main-window.blp',
  ),
  output: '.',
  command: [
    blueprint_compiler, 'batch-compile',
    '@OUTDIR@', '@CURRENT_SOURCE_DIR@', '@INPUT@',
  ],
)

codi_resources = gnome.compile_resources(
  'codi-gtk-resources',
  'io.github.alxmagro.Codi.gresource.xml',
  source_dir: meson.current_build_dir(),
  dependencies: blueprints,
)

install_data(
  'io.github.alxmagro.Codi.desktop.in',
  rename: app_id + '.desktop',
  install_dir: get_option('datadir') / 'applications',
)
