private void test_a_fenced_block_is_painted_in_the_language_it_names () {
    assert_cmpstr (LanguageProbe.style_of ("a.md", "# Title\n\n```js\nconst a = 1;\n```\n", "const"), CompareOperator.EQ, "keyword");
    assert_cmpstr (LanguageProbe.style_of ("a.md", "# Title\n\n```ruby\ndef hi; end\n```\n", "def"), CompareOperator.EQ, "keyword");
}

private void test_headings_are_symbols () {
    var symbols = LanguageProbe.symbols ("a.md", "# Opus\n\nText.\n\n## Install\n\nMore text.\n");

    assert_cmpstrv (symbols, { "Opus: section", "Install: section" });
}

private void test_text_with_no_heading_has_no_symbols () {
    var symbols = LanguageProbe.symbols ("a.md", "Just a paragraph.\n");

    assert_cmpstrv (symbols, {  });
}

private void test_a_backtick_closes () {
    assert_cmpstr (LanguageProbe.type ("a.md", "Run <|>", '`'), CompareOperator.EQ, "Run `<|>`");
}

private void test_an_asterisk_is_plain () {
    assert_cmpstr (LanguageProbe.type ("a.md", "Run <|>", '*'), CompareOperator.EQ, "Run *<|>");
}

private void test_a_fenced_block_follows_its_own_language_s_pairs () {
    assert_cmpstr (LanguageProbe.type ("a.md", "```rust\nlet x = <|>\n```\n", '\''), CompareOperator.EQ, "```rust\nlet x = '<|>\n```\n");
}

void main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/languages/markdown/a_fenced_block_is_painted_in_the_language_it_names", test_a_fenced_block_is_painted_in_the_language_it_names);
    Test.add_func ("/languages/markdown/headings_are_symbols", test_headings_are_symbols);
    Test.add_func ("/languages/markdown/text_with_no_heading_has_no_symbols", test_text_with_no_heading_has_no_symbols);
    Test.add_func ("/languages/markdown/a_backtick_closes", test_a_backtick_closes);
    Test.add_func ("/languages/markdown/an_asterisk_is_plain", test_an_asterisk_is_plain);
    Test.add_func ("/languages/markdown/a_fenced_block_follows_its_own_language_s_pairs", test_a_fenced_block_follows_its_own_language_s_pairs);
    Test.run ();
}
