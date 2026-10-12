// Guards src/themes/syntax/ itself rather than a Model: every bundled
// syntax theme — each owner/theme folder with a theme.json — must load in every
// variant its manifest lists, and style something.

private string themes_directory () {
    return Path.build_filename (Environment.get_variable ("OPUS_THEMES_DIR"), "syntax");
}

/** Every theme's id, `owner/theme`, by the manifest its folder holds. */
private GenericArray<string> bundled_theme_ids () {
    var ids = new GenericArray<string> ();
    try {
        var owners = Dir.open (themes_directory ());
        string? owner;
        while ((owner = owners.read_name ()) != null) {
            var themes = Dir.open (Path.build_filename (themes_directory (), owner));
            string? theme;
            while ((theme = themes.read_name ()) != null) {
                if (FileUtils.test (Path.build_filename (themes_directory (), owner, theme, ThemeManifest.FILE), FileTest.IS_REGULAR)) {
                    ids.add (Path.build_filename (owner, theme));
                }
            }
        }
    } catch (Error e) {
        error ("%s", e.message);
    }
    return ids;
}

private void test_every_bundled_theme_loads_in_every_variant_it_lists () {
    var ids = bundled_theme_ids ();
    assert_cmpuint (ids.length, CompareOperator.GT, 0);
    foreach (unowned string id in ids) {
        try {
            var manifest = ThemeManifest.load (Path.build_filename (themes_directory (), id));
            if (manifest.light != null) {
                assert_cmpint (Theme.load ({ themes_directory () }, id, false).style_keys ().length, CompareOperator.GT, 0);
            }
            if (manifest.dark != null) {
                assert_cmpint (Theme.load ({ themes_directory () }, id, true).style_keys ().length, CompareOperator.GT, 0);
            }
        } catch (ThemeError e) {
            error ("%s: %s", id, e.message);
        }
    }
}

private void test_the_themes_worn_by_default_are_bundled_in_both_variants () {
    try {
        assert_cmpint (Theme.load ({ themes_directory () }, UserSettings.DEFAULT_THEME_SYNTAX, false).style_keys ().length, CompareOperator.GT, 0);
        assert_cmpint (Theme.load ({ themes_directory () }, UserSettings.DEFAULT_THEME_SYNTAX, true).style_keys ().length, CompareOperator.GT, 0);
    } catch (ThemeError e) {
        error ("%s", e.message);
    }
}

void main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/themes/every_bundled_theme_loads_in_every_variant_it_lists", test_every_bundled_theme_loads_in_every_variant_it_lists);
    Test.add_func ("/themes/the_themes_worn_by_default_are_bundled_in_both_variants", test_the_themes_worn_by_default_are_bundled_in_both_variants);
    Test.run ();
}
