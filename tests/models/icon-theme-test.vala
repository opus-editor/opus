// A small fixture theme, not the real bundled "Symbols" one — exercises
// IconTheme's own resolution logic (IconTheme.from_json bypasses
// GResource entirely for exactly this reason) without depending on the
// real theme's 366 definitions staying exactly as they are today.
const string FIXTURE_THEME = """
{
    "iconDefinitions": {
        "document": { "iconPath": "./icons/files/document.svg" },
        "typescript": { "iconPath": "./icons/files/ts.svg" },
        "ts-types": { "iconPath": "./icons/files/ts-types.svg" },
        "dockerfile": { "iconPath": "./icons/files/dockerfile.svg" },
        "folder": { "iconPath": "./icons/folders/folder.svg" },
        "folder-src": { "iconPath": "./icons/folders/folder-src.svg" }
    },
    "fileExtensions": {
        "ts": "typescript",
        "d.ts": "ts-types"
    },
    "fileNames": {
        "dockerfile": "dockerfile"
    },
    "folderNames": {
        "src": "folder-src"
    },
    "file": "document",
    "folder": "folder"
}
""";

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/models/icon-theme/file/extension_match", () => {
        var theme = new IconTheme.from_json (FIXTURE_THEME);

        var path = theme.icon_path_for_file ("app.ts");

        assert_cmpstr (path, CompareOperator.EQ, "/io/github/opus_editor/Opus/icons/symbols/files/ts.svg");
    });

    Test.add_func ("/models/icon-theme/file/exact_name_beats_extension", () => {
        // "Dockerfile" has no extension of its own to match anyway, but
        // this also confirms the fileNames tier is actually consulted
        // before falling through to the generic default.
        var theme = new IconTheme.from_json (FIXTURE_THEME);

        var path = theme.icon_path_for_file ("Dockerfile");

        assert_cmpstr (path, CompareOperator.EQ, "/io/github/opus_editor/Opus/icons/symbols/files/dockerfile.svg");
    });

    Test.add_func ("/models/icon-theme/file/compound_extension_beats_simple_extension", () => {
        var theme = new IconTheme.from_json (FIXTURE_THEME);

        var path = theme.icon_path_for_file ("app.d.ts");

        assert_cmpstr (path, CompareOperator.EQ, "/io/github/opus_editor/Opus/icons/symbols/files/ts-types.svg");
    });

    Test.add_func ("/models/icon-theme/file/matching_is_case_insensitive", () => {
        var theme = new IconTheme.from_json (FIXTURE_THEME);

        var path = theme.icon_path_for_file ("APP.TS");

        assert_cmpstr (path, CompareOperator.EQ, "/io/github/opus_editor/Opus/icons/symbols/files/ts.svg");
    });

    Test.add_func ("/models/icon-theme/file/unknown_name_falls_back_to_default", () => {
        var theme = new IconTheme.from_json (FIXTURE_THEME);

        var path = theme.icon_path_for_file ("README");

        assert_cmpstr (path, CompareOperator.EQ, "/io/github/opus_editor/Opus/icons/symbols/files/document.svg");
    });

    Test.add_func ("/models/icon-theme/folder/exact_name_match", () => {
        var theme = new IconTheme.from_json (FIXTURE_THEME);

        var path = theme.icon_path_for_folder ("src");

        assert_cmpstr (path, CompareOperator.EQ, "/io/github/opus_editor/Opus/icons/symbols/folders/folder-src.svg");
    });

    Test.add_func ("/models/icon-theme/folder/unknown_name_falls_back_to_default", () => {
        var theme = new IconTheme.from_json (FIXTURE_THEME);

        var path = theme.icon_path_for_folder ("some-random-folder");

        assert_cmpstr (path, CompareOperator.EQ, "/io/github/opus_editor/Opus/icons/symbols/folders/folder.svg");
    });

    Test.add_func ("/models/icon-theme/symbols/bundled_resource_loads", () => {
        // Not a resolution-behavior test (those are all above, against
        // the fixture) — just confirms the real bundled theme actually
        // parses and its own declared defaults resolve to *something*,
        // catching a broken gresource.xml/JSON before it ships.
        var theme = new IconTheme.symbols ();

        var path = theme.icon_path_for_file ("some-file-with-no-known-extension");

        assert_true (path.has_prefix ("/io/github/opus_editor/Opus/icons/symbols/"));
    });

    return Test.run ();
}
