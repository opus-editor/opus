private string[] ids_of (CommandBar.Picker picker) {
    string[] ids = {};
    foreach (var item in picker.items) {
        ids += item.id;
    }
    return ids;
}

private CommandBar.Picker open (CommandBar.NumberProvider provider) {
    var picker = new CommandBar.Picker (provider.prefix);
    provider.provide (picker, new Cancellable ());
    return picker;
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/command-bar/number-provider/every-value-of-the-range-is-a-row", () => {
        var provider = new CommandBar.NumberProvider ("Pick", 2, 4);

        var picker = open (provider);

        assert_cmpstrv (ids_of (picker), { "2", "3", "4" });
    });

    Test.add_func ("/command-bar/number-provider/the-none-row-comes-first-in-its-own-words", () => {
        var provider = new CommandBar.NumberProvider ("Pick", 1, 2, "None", "Use the other one");

        var picker = open (provider);

        assert_cmpstr (picker.items[0].id, CompareOperator.EQ, CommandBar.NumberProvider.NONE);
        assert_cmpstr (picker.items[0].label, CompareOperator.EQ, "None");
        assert_cmpstr (picker.items[0].description, CompareOperator.EQ, "Use the other one");
    });

    Test.add_func ("/command-bar/number-provider/what-is-typed-narrows-the-rows", () => {
        var provider = new CommandBar.NumberProvider ("Pick", 1, 16);
        var picker = open (provider);

        picker.text = "1";

        assert_cmpstrv (ids_of (picker), { "1", "10", "11", "12", "13", "14", "15", "16" });
    });

    return Test.run ();
}
