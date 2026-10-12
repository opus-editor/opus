// Functions.Manifest: what function.json may and must say.

private Functions.Manifest parse (string json) {
    try {
        return Functions.Manifest.parse ("/tmp/functions/uppercase", json);
    } catch (Functions.ManifestError e) {
        error (e.message);
    }
}

private string? failure_of (string json) {
    try {
        Functions.Manifest.parse ("/tmp/functions/uppercase", json);
        return null;
    } catch (Functions.ManifestError e) {
        return e.message;
    }
}

private void test_a_full_manifest_is_read () {
    var manifest = parse ("{ \"name\": \"Uppercase\", \"description\": \"Capitals\", \"entry\": \"up.lua\", \"type\": \"transform\", \"input\": \"selection\", \"languages\": [\"lua\", \"ruby\"] }");

    assert_cmpstr (manifest.id, CompareOperator.EQ, "uppercase");
    assert_cmpstr (manifest.name, CompareOperator.EQ, "Uppercase");
    assert_cmpstr (manifest.description, CompareOperator.EQ, "Capitals");
    assert_cmpstr (manifest.entry, CompareOperator.EQ, "/tmp/functions/uppercase/up.lua");
    assert_true (manifest.input == Functions.Scope.SELECTION);
    assert_cmpstrv (manifest.languages, { "lua", "ruby" });
}

private void test_only_the_name_is_required () {
    var manifest = parse ("{ \"name\": \"Uppercase\" }");

    assert_cmpstr (manifest.description, CompareOperator.EQ, "");
    assert_cmpstr (manifest.entry, CompareOperator.EQ, "/tmp/functions/uppercase/main.lua");
    assert_true (manifest.input == Functions.Scope.BOTH);
    assert_cmpint (manifest.languages.length, CompareOperator.EQ, 0);
}

private void test_a_manifest_without_a_name_is_invalid () {
    assert_true (failure_of ("{ \"description\": \"x\" }").contains ("\"name\" is required"));
}

private void test_an_unknown_type_or_input_is_invalid () {
    assert_true (failure_of ("{ \"name\": \"x\", \"type\": \"command\" }").contains ("\"type\""));
    assert_true (failure_of ("{ \"name\": \"x\", \"input\": \"lines\" }").contains ("\"input\""));
}

private void test_languages_must_be_strings () {
    assert_true (failure_of ("{ \"name\": \"x\", \"languages\": \"lua\" }").contains ("\"languages\""));
    assert_true (failure_of ("{ \"name\": \"x\", \"languages\": [1] }").contains ("\"languages\""));
}

private void test_broken_json_is_invalid () {
    assert_true (failure_of ("{ \"name\": ").contains ("not valid JSON"));
}

void main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/models/functions/manifest/a_full_manifest_is_read", test_a_full_manifest_is_read);
    Test.add_func ("/models/functions/manifest/only_the_name_is_required", test_only_the_name_is_required);
    Test.add_func ("/models/functions/manifest/a_manifest_without_a_name_is_invalid", test_a_manifest_without_a_name_is_invalid);
    Test.add_func ("/models/functions/manifest/an_unknown_type_or_input_is_invalid", test_an_unknown_type_or_input_is_invalid);
    Test.add_func ("/models/functions/manifest/languages_must_be_strings", test_languages_must_be_strings);
    Test.add_func ("/models/functions/manifest/broken_json_is_invalid", test_broken_json_is_invalid);
    Test.run ();
}
