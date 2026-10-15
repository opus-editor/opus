/**
 * A theme change reaches text already painted, end to end through the
 * real window: a theme that only recolors restyles the tags in place,
 * and one that changes which captures are styled paints again — a
 * capture it styles anew wins where it used to lose, one it drops
 * comes off. The theme is switched the way a user does it, by editing
 * settings.json while it is open.
 */

private const uint DISPLAY = 139;

private string write_fixture (string name, string contents) throws Error {
    var root_path = DirUtils.make_tmp ("opus-theme-switch-test-XXXXXX");
    var path = Path.build_filename (root_path, name);
    FileUtils.set_contents (path, contents);
    return path;
}

private string settings_naming (string theme) {
    return "{ \"theme.syntax\": \"opus-editor/%s\" }".printf (theme);
}

/** Opus under `theme`, showing `{"a": 12}` as JSON — offsets 1-3 are the key `"a"`, 6-7 the number — with settings.json open behind it so a rewrite is picked up. */
private SystemTestSession opus_showing_json_under (string theme) throws Error {
    var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), DISPLAY, null, settings_naming (theme));
    opus.open_tab (opus.settings_path);
    opus.open_tab (write_fixture ("a.json", "{\"a\": 12}"));
    return opus;
}

private void switch_to (SystemTestSession opus, string theme) throws Error {
    opus.write_settings_json (settings_naming (theme));
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/system/theme_switch/a_theme_that_only_recolors_restyles_the_text_in_place", () => {
        try {
            var opus = opus_showing_json_under ("plain-constants");
            opus.wait_for_syntax_style (6, "constant");

            switch_to (opus, "numeric-constants");

            opus.wait_for_syntax_style (6, "constant.numeric");
            assert_cmpstr (opus.syntax_style_at (1), CompareOperator.EQ, "string");
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    // The key "a" is both @string and @variable.other.member; the later
    // pattern wins only once the theme styles it, so this takes a repaint.
    Test.add_func ("/system/theme_switch/a_theme_that_styles_a_new_capture_repaints_where_it_now_wins", () => {
        try {
            var opus = opus_showing_json_under ("plain-constants");
            opus.wait_for_syntax_style (1, "string");

            switch_to (opus, "member-keys");

            opus.wait_for_syntax_style (1, "variable");
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/theme_switch/a_theme_that_drops_a_capture_unpaints_it", () => {
        try {
            var opus = opus_showing_json_under ("plain-constants");
            opus.wait_for_syntax_style (6, "constant");

            switch_to (opus, "member-keys");

            opus.wait_for_syntax_style (6, "");
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    return Test.run ();
}
