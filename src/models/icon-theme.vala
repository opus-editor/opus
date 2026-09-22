/**
 * Resolves a file or folder's own name to the {@link GLib.Resource} path of
 * its icon SVG, driven entirely by a real icon-theme JSON — parsed as-is,
 * no pre-processing (see {@link load_theme}). `.symbols()` loads the
 * bundled "Symbols" theme (github.com/miguelsolorio/symbols, MIT — see
 * data/icons/symbols/LICENSE, and tools/generate-default-icon-theme.py
 * for how its assets got there); a future "let the user pick a different
 * icon theme" feature would add sibling constructors (or make the JSON
 * source settable) rather than anything calling code here needs to
 * change — {@link icon_path_for_file}/{@link icon_path_for_folder} are
 * already theme-agnostic.
 */
public class IconTheme : Object {
    private const string RESOURCE_PATH = "/io/github/nowaos/Opus/icons/symbols/symbol-icon-theme.json";
    private const string RESOURCE_PREFIX = "/io/github/nowaos/Opus/icons/symbols/";
    private const string ICON_PATH_PREFIX = "./icons/";

    private HashTable<string, string> icon_paths = new HashTable<string, string> (str_hash, str_equal);
    private HashTable<string, string> file_extensions = new HashTable<string, string> (str_hash, str_equal);
    private HashTable<string, string> file_names = new HashTable<string, string> (str_hash, str_equal);
    private HashTable<string, string> folder_names = new HashTable<string, string> (str_hash, str_equal);
    private string default_file_icon_id;
    private string default_folder_icon_id;

    public IconTheme.symbols () {
        Bytes bytes;
        try {
            bytes = resources_lookup_data (RESOURCE_PATH, ResourceLookupFlags.NONE);
        } catch (Error e) {
            // Bundled at build time (see the gresource.xml this app ships
            // with) — missing here means a broken build, not a real
            // runtime condition to degrade gracefully from.
            error ("bundled Symbols icon theme resource missing: %s", e.message);
        }
        load_theme ((string) bytes.get_data (), (ssize_t) bytes.get_size ());
    }

    /** Builds a theme straight from `json_text` — same shape as the real bundled one, minus GResource — so model tests can exercise the resolution logic against small fixture themes instead of the real 366-icon one. */
    public IconTheme.from_json (string json_text) {
        load_theme (json_text, json_text.length);
    }

    private void load_theme (string json_text, ssize_t length) {
        var parser = new Json.Parser ();
        try {
            parser.load_from_data (json_text, length);
        } catch (Error e) {
            error ("malformed icon theme JSON: %s", e.message);
        }

        var root = parser.get_root ()?.get_object ();
        if (root == null) {
            error ("icon theme JSON has no top-level object");
        }

        var definitions = root.get_object_member ("iconDefinitions");
        foreach (var id in definitions.get_members ()) {
            var icon_path = definitions.get_object_member (id).get_string_member ("iconPath");
            var relative = icon_path.has_prefix (ICON_PATH_PREFIX) ? icon_path.substring (ICON_PATH_PREFIX.length) : icon_path;
            icon_paths[id] = RESOURCE_PREFIX + relative;
        }

        load_string_map (root.get_object_member ("fileExtensions"), file_extensions);
        load_string_map (root.get_object_member ("fileNames"), file_names);
        load_string_map (root.get_object_member ("folderNames"), folder_names);

        default_file_icon_id = root.get_string_member ("file");
        default_folder_icon_id = root.get_string_member ("folder");
    }

    // Keys are lowercased on load — matches VS Code's own real
    // resolution (`key.toLowerCase()` in its real fileIconThemeData.ts),
    // and the Symbols theme's own JSON does mix case in a few keys (e.g.
    // "CLAUDE.md", "YAML-tmLanguage") that must still match a
    // lowercased query at lookup time.
    private static void load_string_map (Json.Object obj, HashTable<string, string> table) {
        foreach (var key in obj.get_members ()) {
            table[key.down ()] = obj.get_string_member (key);
        }
    }

    /** `file_name`'s own icon — an exact-name match (e.g. "dockerfile") wins over an extension match, itself won by the longest known compound extension (e.g. "d.ts" over plain "ts") — same priority order as VS Code's own real icon theme resolution (fileIconThemeData.ts, checked its source). Never null: falls back to the theme's own generic file icon. */
    public string icon_path_for_file (string file_name) {
        var lower = file_name.down ();
        var id = file_names[lower] ?? extension_icon_id (lower) ?? default_file_icon_id;
        return icon_paths[id];
    }

    /** `folder_name`'s own icon — an exact name match (e.g. "src", "node_modules") if the theme has one, else the theme's own generic folder icon. Never null. */
    public string icon_path_for_folder (string folder_name) {
        var id = folder_names[folder_name.down ()] ?? default_folder_icon_id;
        return icon_paths[id];
    }

    /**
     * The longest dot-suffix of `lower_name` that the theme actually
     * defines an extension for, e.g. "foo.spec.ts" tries "spec.ts" before
     * "ts" — a compound extension like that (or "tar.gz", "d.ts", …) only
     * wins over its own shorter tail when the theme specifically defines
     * it; otherwise this falls through to the shorter one naturally.
     * Ported from the same real algorithm VS Code's own file icon theme
     * uses (fileIconThemeData.ts's per-extension CSS-selector chain is
     * exactly this "longest compound match wins" rule, just expressed as
     * CSS specificity instead of an explicit loop).
     */
    private string? extension_icon_id (string lower_name) {
        var segments = lower_name.split (".");
        for (int i = 1; i < segments.length; i++) {
            var candidate = new StringBuilder ();
            for (int j = i; j < segments.length; j++) {
                if (j > i) {
                    candidate.append_c ('.');
                }
                candidate.append (segments[j]);
            }
            var id = file_extensions[candidate.str];
            if (id != null) {
                return id;
            }
        }
        return null;
    }
}
