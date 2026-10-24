/**
 * The Command Bar's `>` list end to end through the real window: the
 * commands show without a folder, "Set language..." swaps the list for
 * the languages and gives an unsaved file its colors and indentation,
 * and the other two do what their shortcuts do.
 */

private const uint DISPLAY = 101;

/** A folder holding only a 2-space .editorconfig, so Enter's indentation is the same on every machine. */
private string make_folder () throws Error {
    var folder = DirUtils.make_tmp ("opus-commands-test-XXXXXX");
    FileUtils.set_contents (Path.build_filename (folder, ".editorconfig"), "[*]\nindent_style = space\nindent_size = 2\n");
    return folder;
}

/** Picks `language` for the active tab the way a person would: the commands, "Set language...", then the language. */
private void set_language (SystemTestSession opus, string language) throws Error {
    opus.open_commands ();
    opus.command_bar_type (">set language");
    opus.command_bar_accept ();
    opus.command_bar_type (language);
    opus.command_bar_accept ();
}

private string settings_path () {
    return Path.build_filename (Environment.get_tmp_dir (), "opus-test-config-%u".printf (DISPLAY), "opus", "settings.json");
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/system/commands/the_commands_are_listed_with_no_folder_open", () => {
        try {
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), DISPLAY);

            opus.open_commands ();

            assert_cmpstrv (opus.command_bar_items (), { "set-language", "toggle-word-wrap", "reload-functions", "user-settings" });

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/commands/set_language_swaps_the_commands_for_the_languages", () => {
        try {
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), DISPLAY);
            opus.new_file ();
            opus.open_commands ();
            opus.command_bar_type (">set language");

            opus.command_bar_accept ();

            var languages = opus.command_bar_items ();
            assert_true ("ruby" in languages);
            assert_true ("javascript" in languages);
            assert_false ("set-language" in languages);

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/commands/set_language_with_no_tab_open_lists_nothing", () => {
        try {
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), DISPLAY);
            opus.open_commands ();
            opus.command_bar_type (">set language");

            opus.command_bar_accept ();

            assert_cmpint (opus.command_bar_items ().length, CompareOperator.EQ, 0);

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/commands/languages_that_only_live_inside_others_are_not_offered", () => {
        try {
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), DISPLAY);
            opus.new_file ();
            opus.open_commands ();
            opus.command_bar_type (">set language");

            opus.command_bar_accept ();

            var languages = opus.command_bar_items ();
            assert_false ("comment" in languages);
            assert_false ("ecma" in languages);
            assert_false ("markdown.inline" in languages);

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/commands/an_unsaved_file_set_to_a_language_is_painted_as_it", () => {
        try {
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), DISPLAY);
            opus.new_file ();
            opus.type ("def foo");

            set_language (opus, "ruby");

            opus.wait_for_syntax_style (4, "function");

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/commands/an_unsaved_file_set_to_a_language_is_indented_as_it", () => {
        try {
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), DISPLAY, make_folder ());
            opus.new_file ();
            opus.type ("def foo");
            set_language (opus, "ruby");
            opus.wait_for_syntax_style (4, "function");

            opus.type_cmd ("enter");

            opus.assert_editor_text ("def foo\n  ");

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/commands/the_language_stays_with_its_tab", () => {
        try {
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), DISPLAY);
            opus.new_file (); // Untitled-1
            opus.type ("def foo");
            set_language (opus, "ruby");
            opus.wait_for_syntax_style (4, "function");
            opus.new_file (); // Untitled-2, active and plain
            opus.type ("def foo");
            assert_cmpstr (opus.syntax_style_at (4), CompareOperator.EQ, "");

            opus.close_tab ("Untitled-2"); // back to Untitled-1

            opus.wait_for_active_tab ("Untitled-1");
            opus.wait_for_syntax_style (4, "function");

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/commands/auto_detect_is_only_offered_once_a_language_was_picked", () => {
        try {
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), DISPLAY);
            opus.new_file ();
            opus.open_commands ();
            opus.command_bar_type (">set language");
            opus.command_bar_accept ();
            var before_picking = opus.command_bar_items ();
            opus.command_bar_type ("ruby");
            opus.command_bar_accept ();

            opus.open_commands ();
            opus.command_bar_type (">set language");
            opus.command_bar_accept ();

            assert_false ("" in before_picking);
            assert_cmpstr (opus.command_bar_items ()[0], CompareOperator.EQ, "");

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/commands/auto_detect_takes_the_picked_language_back", () => {
        try {
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), DISPLAY);
            opus.new_file ();
            opus.type ("def foo");
            set_language (opus, "ruby");
            opus.wait_for_syntax_style (4, "function");

            set_language (opus, "auto detect");

            opus.wait_for_syntax_style (4, "");

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/commands/user_settings_opens_the_settings_file", () => {
        try {
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), DISPLAY);
            opus.open_commands ();
            opus.command_bar_type (">user settings");

            opus.command_bar_accept ();

            opus.wait_for_active_tab (settings_path ());

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/commands/toggle_word_wrap_wraps_the_active_document", () => {
        try {
            var folder = make_folder ();
            var a = Path.build_filename (folder, "a.rb");
            FileUtils.set_contents (a, "a\n");
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), DISPLAY);
            opus.open_tab (a);
            assert_false (opus.word_wrap ());
            opus.open_commands ();
            opus.command_bar_type (">toggle word wrap");

            opus.command_bar_accept ();

            assert_true (opus.word_wrap ());
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/commands/toggle_word_wrap_is_the_documents_own_not_the_settings", () => {
        try {
            var folder = make_folder ();
            var a = Path.build_filename (folder, "a.rb");
            var b = Path.build_filename (folder, "b.rb");
            FileUtils.set_contents (a, "a\n");
            FileUtils.set_contents (b, "b\n");
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), DISPLAY);
            opus.open_tab (a);
            opus.open_commands ();
            opus.command_bar_type (">toggle word wrap");
            opus.command_bar_accept ();

            opus.open_tab (b);

            assert_false (opus.word_wrap ());
            // The plain key's own line, at the top level's two spaces:
            // the generated file's language.markdown block turns word
            // wrap on for Markdown, four spaces in.
            if (FileUtils.test (settings_path (), FileTest.EXISTS)) {
                string settings;
                FileUtils.get_contents (settings_path (), out settings);
                assert_true (settings.contains ("\n  \"editor.word_wrap\": false"));
            }
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/commands/a_plugins_command_generates_the_editorconfig_and_opens_it", () => {
        try {
            var folder = DirUtils.make_tmp ("opus-commands-test-XXXXXX");
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), DISPLAY, folder);
            opus.open_commands ();
            opus.command_bar_type (">generate .editorconfig");

            opus.command_bar_accept ();

            var path = Path.build_filename (folder, ".editorconfig");
            opus.wait_for_active_tab (path);
            string written;
            FileUtils.get_contents (path, out written);
            assert_true (written.has_prefix ("root = true\n"));
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    return Test.run ();
}
