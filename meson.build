project(
  'codi-gtk', 'vala', 'c',
  version: '0.1.0',
  meson_version: '>= 1.0',
)

app_id = 'io.github.alxmagro.Codi'
gettext_package = 'codi-gtk'

glib_dep = dependency('glib-2.0')
gobject_dep = dependency('gobject-2.0')
gio_dep = dependency('gio-2.0')
gtk_dep = dependency('gtk4')
adwaita_dep = dependency('libadwaita-1')

gnome = import('gnome')
i18n = import('i18n')

blueprint_compiler = find_program('blueprint-compiler')

subdir('data')
subdir('src')
subdir('po')
subdir('tests')
