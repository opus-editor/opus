// The HEEx package (Phoenix templates), ported from Helix: what its queries make the editor do.

private void test_tags_attributes_and_strings_have_their_colors () {
    string text = "<div class=\"x\"><%= @user.name %></div>\n";

    assert_cmpstr (LanguageProbe.style_of ("a.heex", text, "div"), CompareOperator.EQ, "tag");
    assert_cmpstr (LanguageProbe.style_of ("a.heex", text, "class"), CompareOperator.EQ, "attribute");
    assert_cmpstr (LanguageProbe.style_of ("a.heex", text, "\"x\""), CompareOperator.EQ, "string");
}

private void test_a_language_without_an_indent_query_keeps_every_line_level () {
    assert_cmpint (LanguageProbe.enter ("a.heex", "<div><|>"), CompareOperator.EQ, 0);
}

void main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/languages/heex/tags_attributes_and_strings_have_their_colors", test_tags_attributes_and_strings_have_their_colors);
    Test.add_func ("/languages/heex/a_language_without_an_indent_query_keeps_every_line_level", test_a_language_without_an_indent_query_keeps_every_line_level);
    Test.run ();
}
