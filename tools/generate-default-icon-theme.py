#!/usr/bin/env python3
"""
Regenerates Opus's bundled "Symbols" icon theme assets from a local clone
of https://github.com/miguelsolorio/symbols.

Usage: generate-default-icon-theme.py <path-to-symbols-clone>

Copies every SVG the theme's own JSON references, copies that JSON
itself verbatim (src/models/icon-theme.vala parses it at runtime via
json-glib — nothing here pre-processes its contents), and regenerates
the matching <gresource> file list in data/io.github.nowaos.Opus.gresource.xml.
"""
import json
import os
import shutil
import sys

if len(sys.argv) != 2:
    sys.exit(f"usage: {sys.argv[0]} <path-to-symbols-clone>")

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = sys.argv[1]

theme_path = os.path.join(SRC, "src", "symbol-icon-theme.json")
theme = json.load(open(theme_path))

ICONS_SRC = os.path.join(SRC, "src", "icons")
ICONS_DEST = os.path.join(REPO_ROOT, "data", "icons", "symbols")

# 1. Copy every referenced SVG, build id -> "files/xxx.svg" | "folders/xxx.svg"
id_to_rel = {}
for icon_id, defn in sorted(theme["iconDefinitions"].items()):
    rel = os.path.normpath(defn["iconPath"].lstrip("./"))  # e.g. icons/files/ts.svg
    rel = os.path.relpath(rel, "icons")  # -> files/ts.svg
    src_path = os.path.join(ICONS_SRC, rel)
    dest_path = os.path.join(ICONS_DEST, rel)
    os.makedirs(os.path.dirname(dest_path), exist_ok=True)
    shutil.copyfile(src_path, dest_path)
    id_to_rel[icon_id] = rel.replace(os.sep, "/")

print(f"Copied {len(id_to_rel)} SVGs into {ICONS_DEST}")

# 2. Copy the theme's own JSON verbatim — parsed at runtime, not by this
#    script; see src/models/icon-theme.vala.
shutil.copyfile(theme_path, os.path.join(ICONS_DEST, "symbol-icon-theme.json"))
print("Copied symbol-icon-theme.json")

# 3. Copy the upstream LICENSE for attribution.
shutil.copyfile(os.path.join(SRC, "LICENSE"), os.path.join(ICONS_DEST, "LICENSE"))
print("Copied LICENSE")

# 4. Splice a generated <gresource> file list into the existing gresource.xml,
#    inside its "icons" prefix block, between generated-block markers so a
#    re-run just replaces the previous block instead of duplicating it.
gresource_path = os.path.join(REPO_ROOT, "data", "io.github.nowaos.Opus.gresource.xml")
xml_src = open(gresource_path, encoding="utf-8").read()

BEGIN = "    <!-- BEGIN generated icon theme assets (see tools/) -->"
END = "    <!-- END generated -->"
file_lines = [
    f'    <file alias="symbols/{rel}" compressed="true">icons/symbols/{rel}</file>'
    for rel in sorted(set(id_to_rel.values()))  # a few ids share one svg (aliases)
]
file_lines.append(
    '    <file alias="symbols/symbol-icon-theme.json" compressed="true">icons/symbols/symbol-icon-theme.json</file>'
)
block = f"{BEGIN}\n" + "\n".join(file_lines) + f"\n{END}"

if BEGIN in xml_src:
    start = xml_src.index(BEGIN)
    end = xml_src.index(END) + len(END)
    xml_src = xml_src[:start] + block + xml_src[end:]
else:
    marker = '  <gresource prefix="/io/github/nowaos/Opus/icons">\n'
    idx = xml_src.index(marker) + len(marker)
    xml_src = xml_src[:idx] + block + "\n" + xml_src[idx:]

open(gresource_path, "w", encoding="utf-8").write(xml_src)
print(f"Updated {gresource_path}")
