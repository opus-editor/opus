#!/usr/bin/env python3
"""
Compiles a UI theme folder (src/themes/ui/base/: theme.json naming its
light and dark files) into the one stylesheet the app loads: every color id becomes a CSS variable the other stylesheets
read — --opus-<id, with . and _ as -> — defined under window:not(.dark)
from its light file and under window.dark from its dark one, both in one
file since the mode switches at runtime. A value is a hex color, a
palette name, or a system.* pseudo-name: a libadwaita color, emitted as
var(--…) so it keeps following the desktop (the accent picked in GNOME)
without recompiling. The libadwaita variables a theme repaints
(--window-bg-color, --headerbar-bg-color, …) are re-pointed to the
theme's own, so libadwaita's widgets follow too; a system.* value never
re-points the variable it comes from.

Usage: compile-ui-theme.py <output.css> <theme dir> [<styles dir>]
Run by data/meson.build at build time; nothing is read at runtime. With
a styles dir, every var(--opus-…) the stylesheets there read must be an
id both themes define, or the build fails naming the file and line.
"""
import glob
import json
import os
import re
import sys

SYSTEM = {
    "system.accent": "--accent-bg-color",
    "system.accent.foreground": "--accent-fg-color",
    "system.accent.text": "--accent-color",
    "system.success": "--success-bg-color",
    "system.success.text": "--success-color",
    "system.warning": "--warning-bg-color",
    "system.warning.text": "--warning-color",
    "system.error": "--error-bg-color",
    "system.error.text": "--error-color",
    "system.window.background": "--window-bg-color",
    "system.window.foreground": "--window-fg-color",
    "system.view.background": "--view-bg-color",
    "system.headerbar.background": "--headerbar-bg-color",
    "system.sidebar.background": "--sidebar-bg-color",
    "system.popover.background": "--popover-bg-color",
    "system.dialog.background": "--dialog-bg-color",
    "system.card.background": "--card-bg-color",
    "system.border": "--border-color",
    "system.shade": "--shade-color",
}

# The libadwaita variable each id repaints, when a theme sets it to a color of its own.
LIBADWAITA = {
    "window.background": "--window-bg-color",
    "window.foreground": "--window-fg-color",
    "headerbar.background": "--headerbar-bg-color",
    "headerbar.foreground": "--headerbar-fg-color",
    "sidebar.background": "--sidebar-bg-color",
    "sidebar.foreground": "--sidebar-fg-color",
    "view.background": "--view-bg-color",
    "view.foreground": "--view-fg-color",
    "popover.background": "--popover-bg-color",
    "popover.foreground": "--popover-fg-color",
    "accent.text": "--accent-color",
    "accent.background": "--accent-bg-color",
    "accent.foreground": "--accent-fg-color",
    "window.border": "--border-color",
    "window.shade": "--shade-color",
}

HEX = re.compile(r"^#([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$")
ID = re.compile(r"^[a-z][a-z0-9_]*(\.[a-z0-9][a-z0-9_]*)*$")


def variable(key):
    return "--opus-" + key.replace(".", "-").replace("_", "-")


def fail(path, key, message):
    sys.exit(f"{path}: {key}: {message}")


def resolve(path, key, value, palette):
    if not ID.match(key):
        fail(path, key, "ids are lower-case snake_case words joined by dots")
    if not isinstance(value, str):
        fail(path, key, "a value must be a string")
    if value in SYSTEM:
        return f"var({SYSTEM[value]})"
    if value.startswith("system."):
        fail(path, key, f"unknown system color {value}; one of {', '.join(sorted(SYSTEM))}")
    if value in palette:
        value = palette[value]
    if not HEX.match(value):
        fail(path, key, f"{value!r} is neither a #rrggbb/#rrggbbaa color, a palette name nor a system.* name")
    return value.lower()


def ids_of(path):
    return set(json.load(open(path, encoding="utf-8")).get("ui", {}))


def check_stylesheets(styles_dir, defined):
    """Every --opus-* a stylesheet reads has to come from the theme."""
    known = {variable(key) for key in defined}
    for css in sorted(glob.glob(os.path.join(styles_dir, "*.css"))):
        for number, line in enumerate(open(css, encoding="utf-8"), 1):
            for name in re.findall(r"var\((--opus-[a-z0-9-]+)\)", line):
                if name not in known:
                    sys.exit(f"{css}:{number}: {name} is not defined by the UI theme (src/themes/ui/base/)")


def rules(path, selector):
    theme = json.load(open(path, encoding="utf-8"))
    palette = theme.get("palette", {})
    for name, color in palette.items():
        if not HEX.match(color):
            fail(path, f"palette.{name}", f"{color!r} is not a #rrggbb/#rrggbbaa color")
    ui = theme.get("ui", {})
    lines = [f"{selector} {{"]
    for key in sorted(ui):
        lines.append(f"  {variable(key)}: {resolve(path, key, ui[key], palette)};")
    for key, name in LIBADWAITA.items():
        if key in ui and not ui[key].startswith("system."):
            lines.append(f"  {name}: var({variable(key)});")
    lines.append("}")
    return "\n".join(lines)


if len(sys.argv) not in (3, 4):
    sys.exit("usage: compile-ui-theme.py <output.css> <theme dir> [<styles dir>]")
output, theme_dir = sys.argv[1:3]
manifest_path = os.path.join(theme_dir, "theme.json")
manifest = json.load(open(manifest_path, encoding="utf-8"))
if "light" not in manifest or "dark" not in manifest:
    sys.exit(f"{manifest_path}: the bundled UI theme needs both a \"light\" and a \"dark\" file")
light = os.path.join(theme_dir, manifest["light"])
dark = os.path.join(theme_dir, manifest["dark"])
if ids_of(light) != ids_of(dark):
    sys.exit(f"{light} and {dark} must define the same ids; the difference: {sorted(ids_of(light) ^ ids_of(dark))}")
css = f"/* Generated by tools/compile-ui-theme.py from {os.path.relpath(theme_dir)} — do not edit. */\n\n"
css += rules(light, "window:not(.dark)") + "\n\n" + rules(dark, "window.dark") + "\n"
if len(sys.argv) == 4:
    check_stylesheets(sys.argv[3], ids_of(light))
with open(output, "w", encoding="utf-8") as out:
    out.write(css)
