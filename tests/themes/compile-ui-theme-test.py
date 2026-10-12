#!/usr/bin/env python3
"""tools/compile-ui-theme.py: what it accepts, what it refuses, and that the bundled base themes compile."""
import json
import os
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TOOL = os.path.join(ROOT, "tools", "compile-ui-theme.py")
UI_THEMES = os.path.join(ROOT, "src", "themes", "ui")
failures = []


def compile_themes(light, dark, styles=None):
    with tempfile.TemporaryDirectory() as directory:
        json.dump({"name": "T", "light": "light.json", "dark": "dark.json"}, open(os.path.join(directory, "theme.json"), "w"))
        for name, theme in (("light", light), ("dark", dark)):
            json.dump(theme, open(os.path.join(directory, f"{name}.json"), "w"))
        output = os.path.join(directory, "theme.css")
        args = [sys.executable, TOOL, output, directory] + ([styles] if styles else [])
        result = subprocess.run(args, capture_output=True, text=True)
        css = open(output).read() if result.returncode == 0 else ""
        return result.returncode, result.stderr.strip(), css


def check(name, condition, detail=""):
    if not condition:
        failures.append(f"{name}: {detail}")


def theme(variant, ui, palette=None):
    return {"name": "T", "variant": variant, "palette": palette or {}, "ui": ui}


# every bundled UI theme compiles, and every --opus-* the stylesheets read is defined by each
for folder in sorted(os.listdir(UI_THEMES)):
    result = subprocess.run([sys.executable, TOOL, os.path.join(tempfile.gettempdir(), f"opus-{folder}.css"), os.path.join(UI_THEMES, folder), os.path.join(ROOT, "src", "styles")], capture_output=True, text=True)
    check(f"bundled theme {folder} compiles", result.returncode == 0, result.stderr)

# a hex, a palette name and a system name each become a variable, under the mode's selector
code, _, css = compile_themes(theme("light", {"editor.cursor": "#112233", "view.background": "paper", "git.added": "system.success.text"}, {"paper": "#FFFFFF"}),
                              theme("dark", {"editor.cursor": "#445566", "view.background": "#000000", "git.added": "system.success.text"}))
check("values compile", code == 0, css)
check("hex", "--opus-editor-cursor: #112233;" in css, css)
check("palette name", "--opus-view-background: #ffffff;" in css, css)
check("system name", "--opus-git-added: var(--success-color);" in css, css)
check("light selector", "window:not(.dark) {" in css and "window.dark {" in css, css)
check("dark value", "--opus-editor-cursor: #445566;" in css, css)
# a color of the theme's own repaints the libadwaita variable; a system one does not
check("libadwaita repointed", "--view-bg-color: var(--opus-view-background);" in css, css)
code, _, css = compile_themes(theme("light", {"accent.text": "system.accent.text"}), theme("dark", {"accent.text": "system.accent.text"}))
check("system accent keeps libadwaita's own", "--accent-color: var(" not in css, css)
code, _, css = compile_themes(theme("light", {"editor.selection": "system.accent@35%"}), theme("dark", {"editor.selection": "system.accent@35%"}))
check("system name with alpha", "--opus-editor-selection: color-mix(in srgb, var(--accent-bg-color) 35%, transparent);" in css, css)
code, _, css = compile_themes(theme("light", {"git.added": "green@18%"}, {"green": "#26A269"}), theme("dark", {"git.added": "green@18%"}, {"green": "#26a269"}))
check("palette name with alpha", "--opus-git-added: #26a2692e;" in css, css)
code, _, css = compile_themes(theme("light", {"sidebar.git.opacity": "75%"}), theme("dark", {"sidebar.git.opacity": "75%"}))
check("an opacity id is a percentage", "--opus-sidebar-git-opacity: 75%;" in css, css)
code, err, _ = compile_themes(theme("light", {"sidebar.git.opacity": "#ffffff"}), theme("dark", {"sidebar.git.opacity": "#ffffff"}))
check("a color in an opacity id fails", code != 0 and "percentage" in err, err)

# refusals name the file and the id
code, err, _ = compile_themes(theme("light", {"editor.cursor": "red"}), theme("dark", {"editor.cursor": "#000000"}))
check("a bad color fails", code != 0 and "editor.cursor" in err and "light.json" in err, err)
code, err, _ = compile_themes(theme("light", {"editor.cursor": "system.nope"}), theme("dark", {"editor.cursor": "system.nope"}))
check("an unknown system name fails", code != 0 and "unknown system color" in err, err)
code, err, _ = compile_themes(theme("light", {"Editor.Cursor": "#000000"}), theme("dark", {"Editor.Cursor": "#000000"}))
check("an id that is not snake_case fails", code != 0 and "snake_case" in err, err)
code, err, _ = compile_themes(theme("light", {"editor.cursor": "#000000"}), theme("dark", {"editor.foreground": "#000000"}))
check("the two themes must define the same ids", code != 0 and "same ids" in err, err)

# a stylesheet reading a variable the theme does not define fails the build, naming the line
with tempfile.TemporaryDirectory() as styles:
    open(os.path.join(styles, "a.css"), "w").write("x {\n  color: var(--opus-editor-cursor);\n  background: var(--opus-missing-one);\n}\n")
    code, err, _ = compile_themes(theme("light", {"editor.cursor": "#000000"}), theme("dark", {"editor.cursor": "#000000"}), styles)
    check("an undefined variable in a stylesheet fails", code != 0 and "a.css:3" in err and "--opus-missing-one" in err, err)

if failures:
    print("\n".join(failures))
    sys.exit(1)
print("ok")
