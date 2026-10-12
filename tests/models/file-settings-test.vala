// FileSettings.Registry: every provider's word on a file, field by field.

private class Fixed : Object, IWorkspaceExtension, FileSettings.IProvider {
    public WorkspaceContext context { get; set; }
    private FileSettings.Values values;
    public Fixed (FileSettings.Values values) { this.values = values; }
    public void activate () {}
    public void deactivate () {}
    public FileSettings.Values settings_for (string path) { return values; }
}

private void test_without_a_provider_every_field_is_null () {
    var registry = new FileSettings.Registry ();

    var values = registry.settings_for ("/r/a.txt");

    assert_true (values.indent_size == null);
    assert_true (values.insert_spaces == null);
    assert_true (values.line_ending == null);
    assert_true (values.trim_trailing_whitespace == null);
    assert_true (values.insert_final_newline == null);
}

private void test_a_providers_fields_come_through () {
    var registry = new FileSettings.Registry ();
    registry.add_provider (new Fixed (new FileSettings.Values () { indent_size = 2, line_ending = Document.LineEnding.CRLF }));

    var values = registry.settings_for ("/r/a.txt");

    assert_true (values.indent_size == 2);
    assert_true (values.line_ending == Document.LineEnding.CRLF);
    assert_true (values.insert_spaces == null);
}

private void test_the_last_provider_with_a_field_wins_and_nulls_leave_the_rest_alone () {
    var registry = new FileSettings.Registry ();
    registry.add_provider (new Fixed (new FileSettings.Values () { indent_size = 2, insert_spaces = true }));
    registry.add_provider (new Fixed (new FileSettings.Values () { indent_size = 4 }));

    var values = registry.settings_for ("/r/a.txt");

    assert_true (values.indent_size == 4);
    assert_true (values.insert_spaces == true);
}

private void test_a_removed_provider_no_longer_counts () {
    var registry = new FileSettings.Registry ();
    var provider = new Fixed (new FileSettings.Values () { indent_size = 2 });
    registry.add_provider (provider);

    registry.remove_provider (provider);

    assert_true (registry.settings_for ("/r/a.txt").indent_size == null);
}

void main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/models/file-settings/without_a_provider_every_field_is_null", test_without_a_provider_every_field_is_null);
    Test.add_func ("/models/file-settings/a_providers_fields_come_through", test_a_providers_fields_come_through);
    Test.add_func ("/models/file-settings/the_last_provider_with_a_field_wins_and_nulls_leave_the_rest_alone", test_the_last_provider_with_a_field_wins_and_nulls_leave_the_rest_alone);
    Test.add_func ("/models/file-settings/a_removed_provider_no_longer_counts", test_a_removed_provider_no_longer_counts);
    Test.run ();
}
