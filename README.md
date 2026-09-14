# codi-gtk

A lightweight source code editor for the GNOME desktop — file tree, tabs, and
an editor pane — built native with GTK4 and Libadwaita, in Vala.

`codi-gtk` is the native sibling of [`codi`](https://github.com/alxmagro/codi)
(Electron + Svelte): same idea, GNOME toolkit instead of a web stack.

## Architecture

MVC, with one twist: a **View** is not a `Gtk.Window`/`Gtk.Widget` — it's a
facade that *owns* one internally and exposes a narrow interface. Controllers
and Models only ever see that interface, never `Gtk`/`Adw` types directly.
See [CLAUDE.md](CLAUDE.md) for the full breakdown, the SOLID mapping, and how
to build the project.

## Building

```shell
meson setup builddir
ninja -C builddir
./builddir/src/codi-gtk
```

## Testing

```shell
meson test -C builddir
```

## License

Copyright (c) 2026-present, Alexandre Magro
