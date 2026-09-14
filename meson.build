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

# All C in this project is Vala-generated GObject boilerplate, never hand-written,
# so these two warnings only ever fire on codegen we don't control.
add_project_arguments(
  '-Wno-discarded-qualifiers', # glib's g_once_init_enter() macro (used by every Vala-generated get_type()) discards volatile
  '-Wno-unused-variable', # valac always emits a *_properties array, even for classes with zero GObject properties
  language: 'c',
)

subdir('data')
subdir('src')
subdir('po')
subdir('tests')
