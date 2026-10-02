private string make_temp_file (uint8[] bytes) {
    string path = Path.build_filename (
        Environment.get_tmp_dir (),
        "opus-document-test-%u-%u".printf (Random.next_int (), Random.next_int ())
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

private void test_untitled_document_starts_clean_and_untitled () {
    var document = Document.untitled ("1", "Untitled-1");

    assert_true (document.is_untitled);
    assert_cmpstr (document.uri, CompareOperator.EQ, "untitled://1");
    assert_null (document.pathname);
    assert_cmpstr (document.name, CompareOperator.EQ, "Untitled-1");
    assert_cmpstr (document.content, CompareOperator.EQ, "");
    assert_false (document.dirty);

    document.content = "typed something";
    assert_true (document.dirty);
}

private void test_untitled_uri_and_title_are_independent () {
    // The uri's own slug is a stable identity key, never shown to the
    // user — it must not have to match `title` (the display text,
    // exactly the kind of string that gets reworded/localized later).
    var document = Document.untitled ("7", "Sem título 7");

    assert_cmpstr (document.uri, CompareOperator.EQ, "untitled://7");
    assert_cmpstr (document.name, CompareOperator.EQ, "Sem título 7");
}

private void test_save_as_clears_untitled_and_moves_the_document_to_the_new_path () {
    string path = Path.build_filename (
        Environment.get_tmp_dir (),
        "opus-document-test-%u-%u".printf (Random.next_int (), Random.next_int ())
    );

    try {
        var document = Document.untitled ("1", "Untitled-1");
        document.content = "hello";

        document.save_as (path);

        assert_false (document.is_untitled);
        assert_cmpstr (document.uri, CompareOperator.EQ, Document.uri_for_path (path));
        assert_cmpstr (document.pathname, CompareOperator.EQ, path);
        assert_cmpstr (document.name, CompareOperator.EQ, Path.get_basename (path));
        assert_false (document.dirty);

        string on_disk;
        FileUtils.get_contents (path, out on_disk);
        assert_cmpstr (on_disk, CompareOperator.EQ, "hello");
    } catch (Error e) {
        error ("unexpected error: %s", e.message);
    } finally {
        FileUtils.remove (path);
    }
}

private void test_is_deleted_does_not_affect_dirty_on_its_own () {
    // EditorController is the one deciding whether a deleted-outside-Opus
    // tab should even set is_deleted at all — only ever on an already-dirty
    // one, a clean tab just closes outright instead. Document itself
    // doesn't need is_deleted to influence dirty, since it's only ever set
    // when dirty is already true from real edits.
    string path = make_temp_file ("original".data);

    try {
        var document = Document.load (path);
        assert_false (document.dirty);

        document.is_deleted = true;
        assert_false (document.dirty);
    } catch (Error e) {
        error ("unexpected error: %s", e.message);
    } finally {
        FileUtils.remove (path);
    }
}

private void test_save_recreates_a_deleted_document_and_clears_the_flag () {
    string path = make_temp_file ("original".data);

    try {
        var document = Document.load (path);
        document.content = "edited before the file vanished";
        document.is_deleted = true;
        FileUtils.remove (path); // the file itself really is gone, same as what set is_deleted in the first place

        document.save ();

        assert_false (document.is_deleted);
        assert_false (document.dirty);
        assert_true (FileUtils.test (path, FileTest.EXISTS));
    } catch (Error e) {
        error ("unexpected error: %s", e.message);
    } finally {
        FileUtils.remove (path);
    }
}

private void test_is_externally_modified_does_not_affect_dirty_on_its_own () {
    string path = make_temp_file ("original".data);

    try {
        var document = Document.load (path);
        assert_false (document.dirty);

        document.is_externally_modified = true;
        assert_false (document.dirty);
    } catch (Error e) {
        error ("unexpected error: %s", e.message);
    } finally {
        FileUtils.remove (path);
    }
}

private void test_reload_replaces_in_memory_content_with_whats_on_disk () {
    string path = make_temp_file ("original".data);

    try {
        var document = Document.load (path);
        document.content = "edited in the buffer, not saved yet";
        document.is_externally_modified = true;
        document.is_deleted = true; // reload() should clear both, regardless of which set it
        FileUtils.set_contents (path, "changed by another program");

        document.reload ();

        assert_cmpstr (document.content, CompareOperator.EQ, "changed by another program");
        assert_false (document.dirty);
        assert_false (document.is_externally_modified);
        assert_false (document.is_deleted);
    } catch (Error e) {
        error ("unexpected error: %s", e.message);
    } finally {
        FileUtils.remove (path);
    }
}

private void test_load_sets_a_file_scheme_uri_and_the_real_pathname () {
    string path = make_temp_file ("content".data);

    try {
        var document = Document.load (path);

        assert_cmpstr (document.uri, CompareOperator.EQ, Document.uri_for_path (path));
        assert_cmpstr (document.pathname, CompareOperator.EQ, path);
        assert_cmpstr (document.name, CompareOperator.EQ, Path.get_basename (path));
    } catch (Error e) {
        error ("unexpected error: %s", e.message);
    } finally {
        FileUtils.remove (path);
    }
}

private void test_move_to_updates_uri_and_pathname_together () {
    string path = make_temp_file ("content".data);
    string new_path = path + "-moved";

    try {
        var document = Document.load (path);
        document.move_to (new_path);

        assert_cmpstr (document.uri, CompareOperator.EQ, Document.uri_for_path (new_path));
        assert_cmpstr (document.pathname, CompareOperator.EQ, new_path);
        assert_cmpstr (document.name, CompareOperator.EQ, Path.get_basename (new_path));
    } catch (Error e) {
        error ("unexpected error: %s", e.message);
    } finally {
        FileUtils.remove (path);
    }
}

private void test_title_falls_back_to_the_bare_name_without_a_pathname () {
    var untitled = Document.untitled ("1", "Untitled-1");
    assert_cmpstr (untitled.title, CompareOperator.EQ, "Untitled-1");
}

private void test_each_document_owns_its_own_independent_cursors_and_history () {
    var a = Document.untitled ("1", "Untitled-1");
    var b = Document.untitled ("2", "Untitled-2");

    assert_nonnull (a.cursors);
    assert_nonnull (a.history);
    assert_true (a.cursors != b.cursors);
    assert_true (a.history != b.history);

    a.cursors.add_cursor_at_click (5);
    assert_cmpint (a.cursors.count, CompareOperator.EQ, 2);
    assert_cmpint (b.cursors.count, CompareOperator.EQ, 1); // untouched by a's own edits
}

int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/models/document/load_save_round_trip", test_load_save_round_trip);
    Test.add_func ("/models/document/dirty_tracking", test_dirty_tracking);
    Test.add_func ("/models/document/preview_document", test_preview_document);
    Test.add_func ("/models/document/invalid_utf8_is_unreadable", test_invalid_utf8_is_unreadable);
    Test.add_func ("/models/document/untitled_document_starts_clean_and_untitled", test_untitled_document_starts_clean_and_untitled);
    Test.add_func ("/models/document/untitled_uri_and_title_are_independent", test_untitled_uri_and_title_are_independent);
    Test.add_func ("/models/document/save_as_clears_untitled_and_moves_the_document_to_the_new_path", test_save_as_clears_untitled_and_moves_the_document_to_the_new_path);
    Test.add_func ("/models/document/load_sets_a_file_scheme_uri_and_the_real_pathname", test_load_sets_a_file_scheme_uri_and_the_real_pathname);
    Test.add_func ("/models/document/move_to_updates_uri_and_pathname_together", test_move_to_updates_uri_and_pathname_together);
    Test.add_func ("/models/document/title_falls_back_to_the_bare_name_without_a_pathname", test_title_falls_back_to_the_bare_name_without_a_pathname);
    Test.add_func ("/models/document/is_deleted_does_not_affect_dirty_on_its_own", test_is_deleted_does_not_affect_dirty_on_its_own);
    Test.add_func ("/models/document/save_recreates_a_deleted_document_and_clears_the_flag", test_save_recreates_a_deleted_document_and_clears_the_flag);
    Test.add_func ("/models/document/is_externally_modified_does_not_affect_dirty_on_its_own", test_is_externally_modified_does_not_affect_dirty_on_its_own);
    Test.add_func ("/models/document/reload_replaces_in_memory_content_with_whats_on_disk", test_reload_replaces_in_memory_content_with_whats_on_disk);
    Test.add_func ("/models/document/each_document_owns_its_own_independent_cursors_and_history", test_each_document_owns_its_own_independent_cursors_and_history);
    return Test.run ();
}
