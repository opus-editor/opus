private string make_temp_file (uint8[] bytes) {
    string path = Path.build_filename (
        Environment.get_tmp_dir (),
        "codi-gtk-document-test-%u-%u".printf (Random.next_int (), Random.next_int ())
    );

    try {
        FileUtils.set_contents (path, (string) bytes, bytes.length);
    } catch (Error e) {
        error ("failed to create fixture file: %s", e.message);
    }

    return path;
}

private void test_load_save_round_trip () {
    string path = make_temp_file ("hello world".data);

    try {
        var document = Document.load (path);
        assert_true (document.readable);
        assert_cmpstr (document.content, CompareOperator.EQ, "hello world");

        document.content = "updated content";
        document.save ();

        string on_disk;
        FileUtils.get_contents (path, out on_disk);
        assert_cmpstr (on_disk, CompareOperator.EQ, "updated content");
    } catch (Error e) {
        error ("unexpected error: %s", e.message);
    } finally {
        FileUtils.remove (path);
    }
}

private void test_dirty_tracking () {
    string path = make_temp_file ("original".data);

    try {
        var document = Document.load (path);
        assert_false (document.dirty);

        document.content = "changed";
        assert_true (document.dirty);

        document.save ();
        assert_false (document.dirty);
    } catch (Error e) {
        error ("unexpected error: %s", e.message);
    } finally {
        FileUtils.remove (path);
    }
}

private void test_preview_document () {
    string path = make_temp_file ("content".data);

    try {
        var document = Document.load (path);
        assert_false (document.is_preview);

        document.is_preview = true;
        assert_true (document.is_preview);
    } catch (Error e) {
        error ("unexpected error: %s", e.message);
    } finally {
        FileUtils.remove (path);
    }
}

private void test_invalid_utf8_is_unreadable () {
    uint8[] invalid_bytes = { 0xff, 0xfe, 0x00, 0x01 };
    string path = make_temp_file (invalid_bytes);

    try {
        var document = Document.load (path);
        assert_false (document.readable);
        assert_cmpstr (document.content, CompareOperator.EQ, "");
        assert_false (document.dirty);
    } catch (Error e) {
        error ("load() must not throw for invalid UTF-8, got: %s", e.message);
    } finally {
        FileUtils.remove (path);
    }
}

int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/models/document/load_save_round_trip", test_load_save_round_trip);
    Test.add_func ("/models/document/dirty_tracking", test_dirty_tracking);
    Test.add_func ("/models/document/preview_document", test_preview_document);
    Test.add_func ("/models/document/invalid_utf8_is_unreadable", test_invalid_utf8_is_unreadable);
    return Test.run ();
}
