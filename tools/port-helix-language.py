#!/usr/bin/env python3
"""
Creates or refreshes bundled language packages from a local clone of
https://github.com/helix-editor/helix.

Usage: tools/port-helix-language.py <path-to-helix-clone> <language>...

For each language it writes languages/<language>/language.json,
translated from Helix's languages.toml (plus the title in TITLES below),
and copies the query files Opus reads. A name Helix has queries for but no languages.toml entry (ecma,
_jsx: query-only languages others inherit from) becomes a package with
no grammar.

A query file whose first line starts with "; Written for Opus" is left
alone: it is one Opus maintains itself, because Helix has none or has
one that falls short.

Run tools/sync-grammars.py afterwards.
"""
import json
import os
import re
import shutil
import sys
import tomllib

# The queries Opus has a feature for. Helix ships more (textobjects,
# rainbows); they come over when what reads them does.
QUERIES = ["highlights", "injections", "locals", "indents", "tags"]

# How each language is written for a person to read: what a list of
# languages shows. Helix has no such thing; a language missing here is
# shown by its name.
TITLES = {
    "bash": "Bash",
    "c": "C",
    "cpp": "C++",
    "css": "CSS",
    "diff": "Diff",
    "dockerfile": "Dockerfile",
    "ejs": "EJS",
    "erb": "ERB",
    "git-commit": "Git Commit",
    "go": "Go",
    "html": "HTML",
    "java": "Java",
    "javascript": "JavaScript",
    "json": "JSON",
    "jsx": "JSX",
    "markdown": "Markdown",
    "meson": "Meson",
    "php": "PHP",
    "python": "Python",
    "ruby": "Ruby",
    "rust": "Rust",
    "scss": "SCSS",
    "sql": "SQL",
    "svelte": "Svelte",
    "toml": "TOML",
    "tsx": "TSX",
    "typescript": "TypeScript",
    "vala": "Vala",
    "vue": "Vue",
    "xml": "XML",
    "yaml": "YAML",
}

# Languages Opus only ships to be embedded in others. Helix lets a file
# be one of them (`.regex`); here that would only put them in the list
# of languages to pick from, where they mean nothing.
EMBEDDED_ONLY = {"jsdoc", "regex"}

LOCAL_MARKER = "; Written for Opus"

if len(sys.argv) < 3:
    sys.exit(f"usage: {sys.argv[0]} <path-to-helix-clone> <language>...")

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HELIX = sys.argv[1]

with open(os.path.join(HELIX, "languages.toml"), "rb") as file:
    config = tomllib.load(file)
languages = {language["name"]: language for language in config["language"]}
grammars = {grammar["name"]: grammar for grammar in config["grammar"]}


def manifest_for(name):
    manifest = {"name": name}
    if name in TITLES:
        manifest["title"] = TITLES[name]
    language = languages.get(name)
    if language is None:
        return manifest

    for key in ("file-types", "shebangs", "injection-regex"):
        claims_files = key != "injection-regex"
        if language.get(key) and not (claims_files and name in EMBEDDED_ONLY):
            manifest[key] = language[key]

    grammar_name = language.get("grammar", name)
    grammar = grammars.get(grammar_name)
    if grammar is not None:
        source = grammar["source"]
        if "git" not in source:
            sys.exit(f"{name}: grammar {grammar_name} has no git source")
        entry = {}
        if grammar_name != name:
            entry["name"] = grammar_name
        entry["repository"] = source["git"]
        entry["rev"] = source["rev"]
        if "subpath" in source:
            entry["path"] = source["subpath"]
        manifest["grammar"] = entry
    return manifest


def dump(manifest):
    text = json.dumps(manifest, indent=2, ensure_ascii=False)
    # One glob per line, like the extensions around it.
    return re.sub(r'\{\s*\n\s*"glob": ("(?:[^"\\]|\\.)*")\s*\n\s*\}', r'{ "glob": \1 }', text) + "\n"


def maintained_here(path):
    """A query Opus keeps its own version of says so on its first line; importing must not undo it."""
    if not os.path.exists(path):
        return False
    with open(path) as file:
        return file.readline().startswith(LOCAL_MARKER)


for name in sys.argv[2:]:
    queries_source = os.path.join(HELIX, "runtime", "queries", name)
    if name not in languages and not os.path.isdir(queries_source):
        sys.exit(f"{name}: Helix has neither a language nor queries by that name")

    package = os.path.join(REPO_ROOT, "languages", name)
    os.makedirs(os.path.join(package, "queries"), exist_ok=True)
    with open(os.path.join(package, "language.json"), "w") as file:
        file.write(dump(manifest_for(name)))

    for query in QUERIES:
        source = os.path.join(queries_source, f"{query}.scm")
        target = os.path.join(package, "queries", f"{query}.scm")
        if os.path.exists(source) and not maintained_here(target):
            shutil.copyfile(source, target)
    print(f"languages/{name}")
