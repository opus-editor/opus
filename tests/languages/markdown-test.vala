private void test_a_fenced_block_is_painted_in_the_language_it_names () {
    assert_cmpstr (LanguageProbe.style_of ("a.md", "# Title\n\n```js\nconst a = 1;\n```\n", "const"), CompareOperator.EQ, "keyword");
    assert_cmpstr (LanguageProbe.style_of ("a.md", "# Title\n\n```ruby\ndef hi; end\n```\n", "def"), CompareOperator.EQ, "keyword");
}

void main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/languages/markdown/a_fenced_block_is_painted_in_the_language_it_names", test_a_fenced_block_is_painted_in_the_language_it_names);
    Test.run ();
}
