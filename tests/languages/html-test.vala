private void test_a_script_is_painted_as_javascript () {
    assert_cmpstr (LanguageProbe.style_of ("a.html", "<script>const n = 1;</script>", "const"), CompareOperator.EQ, "keyword");
    assert_cmpstr (LanguageProbe.style_of ("a.html", "<script>const n = 1;</script>", "1"), CompareOperator.EQ, "constant");
}

private void test_a_style_sheet_is_painted_as_css () {
    assert_cmpstr (LanguageProbe.style_of ("a.html", "<style>a { color: red; }</style>", "red"), CompareOperator.EQ, "constant");
}

private void test_the_tags_around_them_are_painted_as_html () {
    assert_cmpstr (LanguageProbe.style_of ("a.html", "<script>const n = 1;</script>", "script"), CompareOperator.EQ, "tag");
}

private void test_a_quote_opening_an_attribute_value_closes () {
    assert_cmpstr (LanguageProbe.type ("a.html", "<a href=<|>>", '"'), CompareOperator.EQ, "<a href=\"<|>\">");
}

private void test_a_quote_inside_an_attribute_value_is_plain () {
    assert_cmpstr (LanguageProbe.type ("a.html", "<a href=\"x<|>\">", '"'), CompareOperator.EQ, "<a href=\"x\"<|>\">");
}

private void test_a_comment_opener_closes_on_its_last_dash () {
    assert_cmpstr (LanguageProbe.type ("a.html", "<!-<|>", '-'), CompareOperator.EQ, "<!--<|>-->");
}

void main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/languages/html/a_script_is_painted_as_javascript", test_a_script_is_painted_as_javascript);
    Test.add_func ("/languages/html/a_style_sheet_is_painted_as_css", test_a_style_sheet_is_painted_as_css);
    Test.add_func ("/languages/html/the_tags_around_them_are_painted_as_html", test_the_tags_around_them_are_painted_as_html);
    Test.add_func ("/languages/html/a_quote_opening_an_attribute_value_closes", test_a_quote_opening_an_attribute_value_closes);
    Test.add_func ("/languages/html/a_quote_inside_an_attribute_value_is_plain", test_a_quote_inside_an_attribute_value_is_plain);
    Test.add_func ("/languages/html/a_comment_opener_closes_on_its_last_dash", test_a_comment_opener_closes_on_its_last_dash);
    Test.run ();
}
