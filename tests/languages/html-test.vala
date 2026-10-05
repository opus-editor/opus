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

void main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/languages/html/a_script_is_painted_as_javascript", test_a_script_is_painted_as_javascript);
    Test.add_func ("/languages/html/a_style_sheet_is_painted_as_css", test_a_style_sheet_is_painted_as_css);
    Test.add_func ("/languages/html/the_tags_around_them_are_painted_as_html", test_the_tags_around_them_are_painted_as_html);
    Test.run ();
}
