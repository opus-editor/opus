private class Scenario {
    public CommandBar.CommandProvider provider;
    public CommandBar.Picker picker;

    public Scenario () {
        provider = new CommandBar.CommandProvider ({
            new CommandBar.Command ("set-language", "File / Set language..."),
            new CommandBar.Command ("toggle-word-wrap", "Editor / Toggle word wrap"),
            new CommandBar.Command ("user-settings", "User Settings"),
        });
        picker = new CommandBar.Picker (provider.prefix);
        provider.provide (picker, new Cancellable ());
    }

    public string[] ids () {
        string[] ids = {};
        foreach (var item in picker.items) {
            ids += item.id;
        }
        return ids;
    }
}

/** A provider over one registry package ("Shout", input both) and a selection-only one, with a document whose state the test sets. */
private class FunctionScenario {
    public CommandBar.CommandProvider provider;
    public CommandBar.Picker picker;
    public bool has_document = true;
    public bool has_selection = false;

    public FunctionScenario () {
        string root;
        try {
            root = DirUtils.make_tmp ("opus-command-provider-XXXXXX");
            write_package (root, "shout", "Shout", "both");
            write_package (root, "trim", "Trim", "selection");
        } catch (Error e) {
            error (e.message);
        }
        var registry = new Functions.Registry ({ root }, (name) => false);
        provider = new CommandBar.CommandProvider ({ new CommandBar.Command ("user-settings", "User Settings") }, registry, document_state);
        picker = new CommandBar.Picker (provider.prefix);
    }

    private static void write_package (string root, string id, string name, string input) throws Error {
        var directory = Path.build_filename (root, id);
        DirUtils.create_with_parents (directory, 0755);
        FileUtils.set_contents (Path.build_filename (directory, "function.json"), "{ \"name\": \"%s\", \"input\": \"%s\" }".printf (name, input));
        FileUtils.set_contents (Path.build_filename (directory, "main.lua"), "function transform (input) return {} end");
    }

    private bool document_state (out string? language, out bool selected) {
        language = null;
        selected = has_selection;
        return has_document;
    }

    public string[] open () {
        provider.provide (picker, new Cancellable ());
        picker.text = ">";
        string[] ids = {};
        foreach (var item in picker.items) {
            ids += item.id;
        }
        return ids;
    }
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/command-bar/command-provider/the-functions-follow-the-commands-as-file-rows", () => {
        var scenario = new FunctionScenario ();

        assert_cmpstrv (scenario.open (), { "user-settings", "function:document:reindent", "function:document:shout" });
    });

    Test.add_func ("/command-bar/command-provider/a-selection-puts-the-selection-rows-before-the-file-ones", () => {
        var scenario = new FunctionScenario ();
        scenario.has_selection = true;

        assert_cmpstrv (scenario.open (), { "user-settings", "function:selection:shout", "function:selection:trim", "function:document:reindent", "function:document:shout" });
        assert_cmpstr (scenario.picker.items[1].label, CompareOperator.EQ, "Selection > Shout");
        assert_cmpstr (scenario.picker.items[4].label, CompareOperator.EQ, "File > Shout");
    });

    Test.add_func ("/command-bar/command-provider/without-a-document-only-the-commands-show", () => {
        var scenario = new FunctionScenario ();
        scenario.has_document = false;

        assert_cmpstrv (scenario.open (), { "user-settings" });
    });

    Test.add_func ("/command-bar/command-provider/each-group-is-captioned-at-its-first-row", () => {
        var scenario = new FunctionScenario ();
        scenario.open ();

        assert_cmpstr (scenario.picker.items[0].separator_label, CompareOperator.EQ, "commands");
        assert_cmpstr (scenario.picker.items[1].separator_label, CompareOperator.EQ, "functions");
    });

    Test.add_func ("/command-bar/command-provider/a-function-rows-id-says-which-way-it-was-picked", () => {
        string function_id;
        bool on_selection;

        assert_true (CommandBar.CommandProvider.decode_function ("function:selection:shout", out function_id, out on_selection));
        assert_cmpstr (function_id, CompareOperator.EQ, "shout");
        assert_true (on_selection);
        assert_true (CommandBar.CommandProvider.decode_function ("function:document:shout", out function_id, out on_selection));
        assert_false (on_selection);
        assert_false (CommandBar.CommandProvider.decode_function ("user-settings", out function_id, out on_selection));
    });

    Test.add_func ("/command-bar/command-provider/its-prefix-is-the-greater-than-sign", () => {
        var scenario = new Scenario ();

        assert_cmpstr (scenario.provider.prefix, CompareOperator.EQ, ">");
    });

    Test.add_func ("/command-bar/command-provider/the-prefix-alone-lists-every-command-in-the-order-given", () => {
        var scenario = new Scenario ();

        scenario.picker.text = ">";

        assert_cmpstrv (scenario.ids (), { "set-language", "toggle-word-wrap", "user-settings" });
    });

    Test.add_func ("/command-bar/command-provider/every-command-is-listed-before-anything-is-typed", () => {
        var scenario = new Scenario ();

        assert_cmpuint (scenario.picker.items.length, CompareOperator.EQ, 3);
    });

    Test.add_func ("/command-bar/command-provider/a-row-shows-the-commands-label", () => {
        var scenario = new Scenario ();

        scenario.picker.text = ">";

        assert_cmpstr (scenario.picker.items[1].label, CompareOperator.EQ, "Editor / Toggle word wrap");
    });

    Test.add_func ("/command-bar/command-provider/typing-after-the-prefix-narrows-the-commands", () => {
        var scenario = new Scenario ();

        scenario.picker.text = ">wrap";

        assert_cmpstrv (scenario.ids (), { "toggle-word-wrap" });
    });

    Test.add_func ("/command-bar/command-provider/a-space-after-the-prefix-changes-nothing", () => {
        var scenario = new Scenario ();

        scenario.picker.text = "> settings";

        assert_cmpstrv (scenario.ids (), { "user-settings" });
    });

    Test.add_func ("/command-bar/command-provider/accepting-hands-back-the-commands-id", () => {
        var scenario = new Scenario ();
        scenario.picker.text = ">lang";
        string? accepted = null;
        scenario.picker.accepted.connect ((item) => accepted = item.id);

        scenario.picker.accept ();

        assert_cmpstr (accepted, CompareOperator.EQ, "set-language");
    });

    Test.add_func ("/command-bar/command-provider/nothing-matching-leaves-a-message-instead-of-rows", () => {
        var scenario = new Scenario ();

        scenario.picker.text = ">zzz";

        assert_cmpuint (scenario.picker.items.length, CompareOperator.EQ, 0);
        assert_cmpstr (scenario.picker.empty_message, CompareOperator.EQ, "No matching commands");
    });

    Test.add_func ("/command-bar/command-provider/a-closed-picker-is-left-alone", () => {
        var scenario = new Scenario ();
        scenario.picker.text = ">wrap";
        scenario.picker.close ();

        scenario.picker.text = ">";

        assert_cmpuint (scenario.picker.items.length, CompareOperator.EQ, 1);
    });

    return Test.run ();
}
