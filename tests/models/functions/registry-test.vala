// Functions.Registry: which packages end up in the list, and for which language.

private string make_tmp_dir () {
    try {
        return DirUtils.make_tmp ("opus-functions-XXXXXX");
    } catch (Error e) {
        error (e.message);
    }
}

private void write_package (string root, string relative, string name, string extra = "") {
    var directory = Path.build_filename (root, relative);
    DirUtils.create_with_parents (directory, 0755);
    try {
        FileUtils.set_contents (Path.build_filename (directory, "function.json"), "{ \"name\": \"%s\"%s }".printf (name, extra));
        FileUtils.set_contents (Path.build_filename (directory, "main.lua"), "function transform (input) return { input.segments[1].text } end");
    } catch (Error e) {
        error (e.message);
    }
}

private string[] names (GenericArray<Functions.Function> functions) {
    string[] result = {};
    foreach (var function in functions) {
        result += function.name;
    }
    return result;
}

private Functions.Registry registry_over (string[] directories) {
    var registry = new Functions.Registry (directories, (name) => name == "lua" || name == "ruby");
    registry.reload ();
    return registry;
}

private void test_the_native_catalog_and_the_packages_share_one_list () {
    var root = make_tmp_dir ();
    write_package (root, "uppercase", "Uppercase");

    var listed = names (registry_over ({ root }).for_language ("lua"));

    assert_cmpstrv (listed, { "Reindent", "Uppercase" });
}

private void test_nothing_is_read_before_reload () {
    var registry = new Functions.Registry ({ make_tmp_dir () }, (name) => false);

    assert_false (registry.loaded);
    assert_cmpint ((int) registry.for_language (null).length, CompareOperator.EQ, 0);
}

private void test_a_later_directory_overrides_an_earlier_package_of_the_same_id () {
    var bundled = make_tmp_dir ();
    var user = make_tmp_dir ();
    write_package (bundled, "uppercase", "Uppercase");
    write_package (user, "uppercase", "My Uppercase");

    var listed = names (registry_over ({ bundled, user }).for_language (null));

    assert_cmpstrv (listed, { "My Uppercase", "Reindent" });
}

private void test_a_language_folder_lists_its_functions_for_that_language_only () {
    var root = make_tmp_dir ();
    write_package (root, "lua/sort-requires", "Sort requires");

    var registry = registry_over ({ root });

    assert_cmpstrv (names (registry.for_language ("lua")), { "Reindent", "Sort requires" });
    assert_cmpstrv (names (registry.for_language ("ruby")), { "Reindent" });
    assert_cmpstrv (names (registry.for_language (null)), { "Reindent" });
}

private void test_the_manifests_languages_add_to_the_folders () {
    var root = make_tmp_dir ();
    write_package (root, "lua/shared", "Shared", ", \"languages\": [\"ruby\"]");

    var registry = registry_over ({ root });

    assert_true ("Shared" in names (registry.for_language ("lua")));
    assert_true ("Shared" in names (registry.for_language ("ruby")));
}

private void test_a_folder_that_is_neither_a_function_nor_a_language_is_skipped () {
    var root = make_tmp_dir ();
    DirUtils.create_with_parents (Path.build_filename (root, "notes"), 0755);
    write_package (root, "uppercase", "Uppercase");

    var listed = names (registry_over ({ root }).for_language (null));

    assert_cmpstrv (listed, { "Reindent", "Uppercase" });
}

private void test_a_broken_manifest_does_not_take_the_others_down () {
    var root = make_tmp_dir ();
    write_package (root, "uppercase", "Uppercase");
    DirUtils.create_with_parents (Path.build_filename (root, "broken"), 0755);
    try {
        FileUtils.set_contents (Path.build_filename (root, "broken", "function.json"), "{ nope");
    } catch (Error e) {
        error (e.message);
    }

    var listed = names (registry_over ({ root }).for_language (null));

    assert_cmpstrv (listed, { "Reindent", "Uppercase" });
}

private void test_reload_sees_a_package_added_since () {
    var root = make_tmp_dir ();
    var registry = registry_over ({ root });
    write_package (root, "uppercase", "Uppercase");

    registry.reload ();

    assert_true (registry.by_id ("uppercase") != null);
}

void main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/models/functions/registry/the_native_catalog_and_the_packages_share_one_list", test_the_native_catalog_and_the_packages_share_one_list);
    Test.add_func ("/models/functions/registry/nothing_is_read_before_reload", test_nothing_is_read_before_reload);
    Test.add_func ("/models/functions/registry/a_later_directory_overrides_an_earlier_package_of_the_same_id", test_a_later_directory_overrides_an_earlier_package_of_the_same_id);
    Test.add_func ("/models/functions/registry/a_language_folder_lists_its_functions_for_that_language_only", test_a_language_folder_lists_its_functions_for_that_language_only);
    Test.add_func ("/models/functions/registry/the_manifests_languages_add_to_the_folders", test_the_manifests_languages_add_to_the_folders);
    Test.add_func ("/models/functions/registry/a_folder_that_is_neither_a_function_nor_a_language_is_skipped", test_a_folder_that_is_neither_a_function_nor_a_language_is_skipped);
    Test.add_func ("/models/functions/registry/a_broken_manifest_does_not_take_the_others_down", test_a_broken_manifest_does_not_take_the_others_down);
    Test.add_func ("/models/functions/registry/reload_sees_a_package_added_since", test_reload_sees_a_package_added_since);
    Test.run ();
}
