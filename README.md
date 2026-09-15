# Opus

A lightweight source code editor for the GNOME desktop — file tree, tabs, and
an editor pane — built native with GTK4 and Libadwaita, in Vala.

## Prerequisites

- Vala (`valac`) 0.56+
- Meson 1.0+ and Ninja
- GTK4 (4.18+) and Libadwaita (1.7+) development headers
- `blueprint-compiler`
- `gettext` (the full package — `msgfmt`/`xgettext`, not just `gettext-base`)
- [`just`](https://github.com/casey/just), to run the commands below

On Debian/Ubuntu:

```shell
sudo apt install valac meson ninja-build libgtk-4-dev libadwaita-1-dev \
  blueprint-compiler gettext just
```

## Building

```shell
just build
just run [folder]
```

## Testing

```shell
just test
```

## License

Copyright (c) 2026-present, Alexandre Magro
