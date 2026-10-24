/**
 * A language's own pairs end to end (docs/AUTO_CLOSE.md §1): what each
 * bundled package declares decides what closes in its files, and an
 * embedded language — the script of a page, the code of a fence —
 * brings its own pairs along. Each package's declarations are tested in
 * tests/languages; this is the real window reading them.
 */
private const uint DISPLAY = 145;

/** A folder holding `name` with `contents`; returns the file's path. */
private string write_fixture (string name, string contents) throws Error {
    var folder = DirUtils.make_tmp ("opus-auto-close-languages-test-XXXXXX");
    var path = Path.build_filename (folder, name);
    FileUtils.set_contents (path, contents);
    return path;
}

private SystemTestSession open_file (string name, string contents, out string path) throws Error {
    path = write_fixture (name, contents);
    var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), DISPLAY, Path.get_dirname (path));
    opus.open_tab (path);
    return opus;
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/system/auto_close/languages/rust_declares_no_single_quote_pair", () => {
        try {
            string path;
            var opus = open_file ("example.rs", "let x = ", out path);
            opus.set_cursors ({ {0, 8} });

            opus.type ("'");

            opus.assert_editor_text ("let x = '"); // a lifetime, not a string
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/auto_close/languages/rust_angle_brackets_do_not_close", () => {
        try {
            string path;
            var opus = open_file ("example.rs", "fn f", out path);
            opus.set_cursors ({ {0, 4} });

            opus.type ("<");

            opus.assert_editor_text ("fn f<");
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/auto_close/languages/an_html_comment_opener_completes_on_its_last_dash", () => {
        try {
            string path;
            var opus = open_file ("example.html", "<!-", out path);
            opus.set_cursors ({ {0, 3} });

            opus.type ("-");

            opus.assert_editor_text ("<!---->");
            opus.assert_cursors ({ {4, 4} });
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/auto_close/languages/a_block_comment_closes_inside_a_page_s_script", () => {
        try {
            string path;
            var opus = open_file ("example.html", "<script>\n\n</script>", out path);
            opus.set_cursors ({ {1, 0} });

            opus.type ("/*");

            opus.assert_editor_text ("<script>\n/* */\n</script>");
            opus.assert_cursors ({ {11, 11} });
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/auto_close/languages/a_block_comment_does_not_close_in_the_page_itself", () => {
        try {
            string path;
            var opus = open_file ("example.html", "<p></p>\n", out path);
            opus.set_cursors ({ {1, 0} });

            opus.type ("/*");

            opus.assert_editor_text ("<p></p>\n/*");
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/auto_close/languages/a_markdown_backtick_closes", () => {
        try {
            string path;
            var opus = open_file ("example.md", "Run ", out path);
            opus.set_cursors ({ {0, 4} });

            opus.type ("`");

            opus.assert_editor_text ("Run ``");
            opus.assert_cursors ({ {5, 5} });
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/auto_close/languages/a_markdown_fence_follows_its_own_language", () => {
        try {
            string path;
            var opus = open_file ("example.md", "```rust\nlet x = \n```\n", out path);
            opus.set_cursors ({ {1, 8} });

            opus.type ("'");

            opus.assert_editor_text ("```rust\nlet x = '\n```\n");
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    return Test.run ();
}
