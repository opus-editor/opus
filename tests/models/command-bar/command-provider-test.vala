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

int main (string[] args) {
    Test.init (ref args);

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
