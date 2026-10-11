// The Just package, ported from Helix — its tags query is Opus's own.

private void test_a_recipe_header_goes_one_level_in () {
    assert_cmpint (LanguageProbe.enter ("justfile", "build:<|>"), CompareOperator.EQ, 1);
}

private void test_recipes_and_settings_are_listed () {
    var symbols = LanguageProbe.symbols ("justfile", "version := \"1\"\n\nbuild:\n    ninja\n\ntest: build\n    meson test\n");

    assert_cmpstrv (symbols, { "version: constant", "build: function", "test: function" });
}

private void test_keywords_comments_strings_and_recipes_have_their_colors () {
    string text = "set shell := [\"bash\", \"-c\"]\n\n# builds\nbuild:\n    ninja\n";

    assert_cmpstr (LanguageProbe.style_of ("justfile", text, "set"), CompareOperator.EQ, "keyword");
    assert_cmpstr (LanguageProbe.style_of ("justfile", text, "\"bash\""), CompareOperator.EQ, "string");
    assert_cmpstr (LanguageProbe.style_of ("justfile", text, "# builds"), CompareOperator.EQ, "comment");
    assert_cmpstr (LanguageProbe.style_of ("justfile", text, "build:"), CompareOperator.EQ, "function");
}

void main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/languages/just/a_recipe_header_goes_one_level_in", test_a_recipe_header_goes_one_level_in);
    Test.add_func ("/languages/just/recipes_and_settings_are_listed", test_recipes_and_settings_are_listed);
    Test.add_func ("/languages/just/keywords_comments_strings_and_recipes_have_their_colors", test_keywords_comments_strings_and_recipes_have_their_colors);
    Test.run ();
}
