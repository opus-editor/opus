/**
 * Indentation that follows the language, end to end through the real
 * window: Enter goes one level in after a line that opens a block —
 * each cursor judged by its own line — and typing what closes a block
 * pulls that line back out, as one undo step with the typing.
 *
 * enter-indent-test covers the baseline every file gets, language or
 * not; this one needs a file a bundled language package claims.
 */

/** A folder holding a 2-space .editorconfig and `name` with `contents`; returns the file's path. */
private string write_fixture (string name, string contents) throws Error {
    var folder = DirUtils.make_tmp ("opus-smart-indent-test-XXXXXX");
    FileUtils.set_contents (Path.build_filename (folder, ".editorconfig"), "[*]\nindent_style = space\nindent_size = 2\n");
    var path = Path.build_filename (folder, name);
    FileUtils.set_contents (path, contents);
    return path;
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/system/smart_indent/enter_after_a_method_header_goes_one_level_in", () => {
        try {
            var path = write_fixture ("example.rb", "def foo(arg)");
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), 98, Path.get_dirname (path));
            opus.open_tab (path);
            opus.set_cursors ({ {0, 12} });

            opus.type_cmd ("enter");

            opus.assert_editor_text ("def foo(arg)\n  ");

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/smart_indent/enter_after_a_header_without_parentheses_goes_one_level_in", () => {
        try {
            var path = write_fixture ("example.rb", "def foo");
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), 98, Path.get_dirname (path));
            opus.open_tab (path);
            opus.set_cursors ({ {0, 7} });

            opus.type_cmd ("enter");

            opus.assert_editor_text ("def foo\n  ");

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/smart_indent/enter_after_a_method_header_inside_a_class_goes_one_level_in", () => {
        try {
            var path = write_fixture ("example.rb", "class Foo\n  def bar\n    1\n  end\n\n  def foo(arg)\nend\n");
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), 98, Path.get_dirname (path));
            opus.open_tab (path);
            opus.set_cursors ({ {5, 14} }); // after `  def foo(arg)`

            opus.type_cmd ("enter");

            opus.assert_editor_text ("class Foo\n  def bar\n    1\n  end\n\n  def foo(arg)\n    \nend\n");

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/smart_indent/a_typed_method_is_indented_and_closed_as_it_goes", () => {
        try {
            var path = write_fixture ("example.rb", "");
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), 98, Path.get_dirname (path));
            opus.open_tab (path);

            opus.type ("def foo");
            opus.type_cmd ("enter");
            opus.type ("bar");
            opus.type_cmd ("enter");
            opus.type ("end");

            opus.assert_editor_text ("def foo\n  bar\nend");

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/smart_indent/each_cursor_is_indented_by_its_own_line", () => {
        try {
            var path = write_fixture ("example.rb", "def foo(arg)\n\nbar");
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), 98, Path.get_dirname (path));
            opus.open_tab (path);
            opus.set_cursors ({ {0, 12}, {2, 3} }); // after the method header, after `bar`

            opus.type_cmd ("enter");

            opus.assert_editor_text ("def foo(arg)\n  \n\nbar\n");

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/smart_indent/two_method_headers_each_open_a_level", () => {
        try {
            var path = write_fixture ("example.rb", "def foo(arg)\n\ndef bar(arg)");
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), 98, Path.get_dirname (path));
            opus.open_tab (path);
            opus.set_cursors ({ {0, 12}, {2, 12} });

            opus.type_cmd ("enter");

            opus.assert_editor_text ("def foo(arg)\n  \n\ndef bar(arg)\n  ");

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/smart_indent/typing_a_block_closer_pulls_its_line_out", () => {
        try {
            var path = write_fixture ("example.rb", "def foo(arg)\n  puts arg\n  ");
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), 98, Path.get_dirname (path));
            opus.open_tab (path);
            opus.set_cursors ({ {2, 2} });

            opus.type ("end");

            opus.assert_editor_text ("def foo(arg)\n  puts arg\nend");

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/smart_indent/one_undo_takes_back_the_closer_and_its_indentation", () => {
        try {
            var path = write_fixture ("example.rb", "def foo(arg)\n  puts arg\n  ");
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), 98, Path.get_dirname (path));
            opus.open_tab (path);
            opus.set_cursors ({ {2, 2} });
            opus.type ("end");

            opus.type_cmd ("undo");

            opus.assert_editor_text ("def foo(arg)\n  puts arg\n  ");

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    Test.add_func ("/system/smart_indent/a_closer_spelled_inside_a_line_moves_nothing", () => {
        try {
            var path = write_fixture ("example.rb", "def foo(arg)\n  puts ");
            var opus = new SystemTestSession (Environment.get_variable ("OPUS_BINARY_PATH"), 98, Path.get_dirname (path));
            opus.open_tab (path);
            opus.set_cursors ({ {1, 7} });

            opus.type ("end");

            opus.assert_editor_text ("def foo(arg)\n  puts end");

            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    return Test.run ();
}
