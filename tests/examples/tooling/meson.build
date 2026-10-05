project(
  'locales', 'vala', 'c',
  version: '0.1.0',
  meson_version: '>= 1.0',
)

glib_dep = dependency('glib-2.0')
gobject_dep = dependency('gobject-2.0')

# Debug-only logging compiles out of a release build.
if get_option('buildtype') == 'debug'
  add_project_arguments('--define=DEBUG', language: 'vala')
endif

sources = files(
  'locale.vala',
  'locale-matcher.vala',
)

executable(
  'locales',
  sources,
  dependencies: [glib_dep, gobject_dep],
  install: true,
)
