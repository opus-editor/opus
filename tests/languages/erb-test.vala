private void test_the_ruby_between_the_tags_is_painted_as_ruby () {
    assert_cmpstr (LanguageProbe.style_of ("a.html.erb", "<% @items.each do |item| %>\n<li><%= item.name %></li>\n<% end %>", "each"), CompareOperator.EQ, "function");
    assert_cmpstr (LanguageProbe.style_of ("a.html.erb", "<% @items.each do |item| %>\n<li><%= item.name %></li>\n<% end %>", "do"), CompareOperator.EQ, "keyword");
}

private void test_the_markup_around_it_is_painted_as_html () {
    assert_cmpstr (LanguageProbe.style_of ("a.html.erb", "<% @items.each do |item| %>\n<li><%= item.name %></li>\n<% end %>", "li"), CompareOperator.EQ, "tag");
}

void main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/languages/erb/the_ruby_between_the_tags_is_painted_as_ruby", test_the_ruby_between_the_tags_is_painted_as_ruby);
    Test.add_func ("/languages/erb/the_markup_around_it_is_painted_as_html", test_the_markup_around_it_is_painted_as_html);
    Test.run ();
}
