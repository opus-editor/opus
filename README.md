# Opus

A lightweight source code editor for the GNOME desktop — file tree, tabs, and
an editor pane — built native with GTK4 and Libadwaita, in Vala.

## Building

```shell
meson setup builddir
ninja -C builddir
./builddir/src/opus
```

## Testing

```shell
meson test -C builddir
```

## License

Copyright (c) 2026-present, Alexandre Magro
