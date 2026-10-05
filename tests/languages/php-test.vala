private void test_an_open_brace_goes_one_level_in () {
    assert_cmpint (LanguageProbe.enter ("a.php", "<?php\nfunction f() {<|>"), CompareOperator.EQ, 1);
}

private void test_the_html_around_the_php_is_painted_as_html () {
    assert_cmpstr (LanguageProbe.style_of ("a.php", "<h1><?php echo \"hi\"; ?></h1>", "h1"), CompareOperator.EQ, "tag");
    assert_cmpstr (LanguageProbe.style_of ("a.php", "<h1><?php echo \"hi\"; ?></h1>", "echo"), CompareOperator.EQ, "keyword");
}

void main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/languages/php/an_open_brace_goes_one_level_in", test_an_open_brace_goes_one_level_in);
    Test.add_func ("/languages/php/the_html_around_the_php_is_painted_as_html", test_the_html_around_the_php_is_painted_as_html);
    Test.run ();
}
