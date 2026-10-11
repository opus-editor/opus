// The Blueprint package (GTK's UI language), ported from Helix: highlights only.

private void test_keywords_objects_properties_and_comments_have_their_colors () {
    string text = "using Gtk 4.0;\n\n// root\nGtk.Box {\n  orientation: vertical;\n  Gtk.Label { label: \"hi\"; }\n}\n";

    assert_cmpstr (LanguageProbe.style_of ("a.blp", text, "using"), CompareOperator.EQ, "keyword");
    assert_cmpstr (LanguageProbe.style_of ("a.blp", text, "// root"), CompareOperator.EQ, "comment");
    assert_cmpstr (LanguageProbe.style_of ("a.blp", text, "orientation"), CompareOperator.EQ, "variable");
    assert_cmpstr (LanguageProbe.style_of ("a.blp", text, "\"hi\""), CompareOperator.EQ, "string");
}

private void test_a_language_without_an_indent_query_keeps_every_line_level () {
    assert_cmpint (LanguageProbe.enter ("a.blp", "Gtk.Box {<|>"), CompareOperator.EQ, 0);
}

void main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/languages/blueprint/keywords_objects_properties_and_comments_have_their_colors", test_keywords_objects_properties_and_comments_have_their_colors);
    Test.add_func ("/languages/blueprint/a_language_without_an_indent_query_keeps_every_line_level", test_a_language_without_an_indent_query_keeps_every_line_level);
    Test.run ();
}
