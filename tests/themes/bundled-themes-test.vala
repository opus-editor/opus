// Guards themes/ itself rather than a Model: every bundled theme must
// load, and the two the editor wears by default must be among them.
// OPUS_THEMES_DIR is set by tests/meson.build.

/** Every theme under `directory`, as the name it is loaded by: its path from the themes directory, without the `.json`. */
private void collect_theme_names (string themes, string directory, GenericArray<string> names) {
    try {
        var dir = Dir.open (Path.build_filename (themes, directory));
        string? entry;
        while ((entry = dir.read_name ()) != null) {
            string relative = directory == "" ? entry : Path.build_filename (directory, entry);
            if (FileUtils.test (Path.build_filename (themes, relative), FileTest.IS_DIR)) {
                collect_theme_names (themes, relative, names);
            } else if (relative.has_suffix (".json")) {
                names.add (relative.substring (0, relative.length - ".json".length));
            }
        }
    } catch (Error e) {
        error ("%s", e.message);
    }
}

private GenericArray<string> bundled_theme_names () {
    var names = new GenericArray<string> ();
    collect_theme_names (Environment.get_variable ("OPUS_THEMES_DIR"), "", names);
    return names;
}

private void test_every_bundled_theme_loads () {
    string themes = Environment.get_variable ("OPUS_THEMES_DIR");
    var names = bundled_theme_names ();

    assert_cmpuint (names.length, CompareOperator.GT, 0);
    foreach (unowned string name in names) {
        try {
            Theme.load ({ themes }, name);
        } catch (ThemeError e) {
            error ("%s: %s", name, e.message);
        }
    }
}

private void test_every_bundled_theme_styles_something () {
    string themes = Environment.get_variable ("OPUS_THEMES_DIR");

    foreach (unowned string name in bundled_theme_names ()) {
        try {
            var theme = Theme.load ({ themes }, name);
            assert_cmpint (theme.style_keys ().length, CompareOperator.GT, 0);
        } catch (ThemeError e) {
            error ("%s: %s", name, e.message);
        }
    }
}

private void test_the_theme_worn_by_default_in_light_mode_is_bundled () {
    var names = bundled_theme_names ();

    assert_true (names.find_with_equal_func (UserSettings.DEFAULT_THEME_LIGHT, str_equal));
}

private void test_the_theme_worn_by_default_in_dark_mode_is_bundled () {
    var names = bundled_theme_names ();

    assert_true (names.find_with_equal_func (UserSettings.DEFAULT_THEME_DARK, str_equal));
}

void main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/themes/every_bundled_theme_loads", test_every_bundled_theme_loads);
    Test.add_func ("/themes/every_bundled_theme_styles_something", test_every_bundled_theme_styles_something);
    Test.add_func ("/themes/the_theme_worn_by_default_in_light_mode_is_bundled", test_the_theme_worn_by_default_in_light_mode_is_bundled);
    Test.add_func ("/themes/the_theme_worn_by_default_in_dark_mode_is_bundled", test_the_theme_worn_by_default_in_dark_mode_is_bundled);
    Test.run ();
}
