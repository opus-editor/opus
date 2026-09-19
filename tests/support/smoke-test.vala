/**
 * A test of the test harness itself, not of Opus — proves the whole
 * chain SystemTestSession relies on actually works (subprocess spawn,
 * Broadway, D-Bus, the dynamic proxy, typing, reading the result back)
 * before any real test in tests/system/ depends on it. Lives in
 * tests/support/, not tests/system/, for exactly that reason.
 */
int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/support/smoke/type_and_read_back", () => {
        string opus_binary_path = Environment.get_variable ("OPUS_BINARY_PATH");
        assert_nonnull (opus_binary_path);

        try {
            var opus = new SystemTestSession (opus_binary_path, 90);
            opus.new_file ();
            opus.editor_write ("hello");
            opus.assert_editor_text ("hello");
            opus.close ();
        } catch (Error e) {
            error ("unexpected error: %s", e.message);
        }
    });

    return Test.run ();
}
