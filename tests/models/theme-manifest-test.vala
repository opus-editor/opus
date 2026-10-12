// ThemeManifest: a theme folder's theme.json.

private ThemeManifest parse (string json) {
    try {
        return ThemeManifest.parse ("/tmp/themes/syntax/opus-editor/github-theme", json);
    } catch (ThemeError e) {
        error ("%s", e.message);
    }
}

private string? failure_of (string json) {
    try {
        ThemeManifest.parse ("/tmp/themes/syntax/opus-editor/github-theme", json);
        return null;
    } catch (ThemeError e) {
        return e.message;
    }
}

private void test_owner_and_folder_are_the_id_and_the_files_are_resolved_inside_it () {
    var manifest = parse ("""{ "name": "GitHub", "light": "light.json", "dark": "dark.json" }""");

    assert_cmpstr (manifest.id, CompareOperator.EQ, "opus-editor/github-theme");
    assert_cmpstr (manifest.name, CompareOperator.EQ, "GitHub");
    assert_cmpstr (manifest.file_for (false), CompareOperator.EQ, "/tmp/themes/syntax/opus-editor/github-theme/light.json");
    assert_cmpstr (manifest.file_for (true), CompareOperator.EQ, "/tmp/themes/syntax/opus-editor/github-theme/dark.json");
}

private void test_a_theme_may_have_one_variant_only () {
    var manifest = parse ("""{ "dark": "dark.json" }""");

    assert_cmpstr (manifest.name, CompareOperator.EQ, "github-theme");
    assert_null (manifest.file_for (false));
    assert_cmpstr (manifest.file_for (true), CompareOperator.EQ, "/tmp/themes/syntax/opus-editor/github-theme/dark.json");
}

private void test_a_manifest_with_no_variant_is_invalid () {
    assert_true (failure_of ("""{ "name": "Empty" }""").contains ("\"light\" or a \"dark\""));
}

private void test_a_variant_that_is_not_a_file_name_is_invalid () {
    assert_true (failure_of ("""{ "light": 1 }""").contains ("\"light\" must be a string"));
}

private void test_broken_json_is_invalid () {
    assert_true (failure_of ("{ ").contains ("not valid JSON"));
}

void main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/models/theme-manifest/owner_and_folder_are_the_id_and_the_files_are_resolved_inside_it", test_owner_and_folder_are_the_id_and_the_files_are_resolved_inside_it);
    Test.add_func ("/models/theme-manifest/a_theme_may_have_one_variant_only", test_a_theme_may_have_one_variant_only);
    Test.add_func ("/models/theme-manifest/a_manifest_with_no_variant_is_invalid", test_a_manifest_with_no_variant_is_invalid);
    Test.add_func ("/models/theme-manifest/a_variant_that_is_not_a_file_name_is_invalid", test_a_variant_that_is_not_a_file_name_is_invalid);
    Test.add_func ("/models/theme-manifest/broken_json_is_invalid", test_broken_json_is_invalid);
    Test.run ();
}
