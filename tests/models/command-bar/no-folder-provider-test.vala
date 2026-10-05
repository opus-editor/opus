private CommandBar.Picker opened_with (string text) {
    var provider = new CommandBar.NoFolderProvider ();
    var picker = new CommandBar.Picker (provider.prefix);
    provider.provide (picker, new Cancellable ());
    picker.text = text;
    return picker;
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/command-bar/no-folder-provider/it-answers-for-text-with-no-prefix", () => {
        var provider = new CommandBar.NoFolderProvider ();

        assert_cmpstr (provider.prefix, CompareOperator.EQ, "");
    });

    Test.add_func ("/command-bar/no-folder-provider/it-lists-nothing", () => {
        var picker = opened_with ("");

        assert_cmpuint (picker.items.length, CompareOperator.EQ, 0);
    });

    Test.add_func ("/command-bar/no-folder-provider/it-says-a-folder-is-needed-and-which-prefixes-are-not", () => {
        var picker = opened_with ("");

        assert_cmpstr (picker.empty_message, CompareOperator.EQ, "Open a folder to search files\n: Go to line\n# Go to symbol\n> Run commands");
    });

    Test.add_func ("/command-bar/no-folder-provider/typing-a-file-name-lists-nothing-and-says-the-same", () => {
        var picker = opened_with ("readme");

        assert_cmpuint (picker.items.length, CompareOperator.EQ, 0);
        assert_cmpstr (picker.empty_message, CompareOperator.EQ, "Open a folder to search files\n: Go to line\n# Go to symbol\n> Run commands");
    });

    return Test.run ();
}
