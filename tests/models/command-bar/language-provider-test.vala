// Lists language packages written to a temporary directory. No grammar
// is ever loaded: listing a language doesn't need one.

private class Scenario {
    public CommandBar.LanguageProvider provider;
    public CommandBar.Picker picker;
    private string directory;

    public Scenario () {
        directory = Path.build_filename (Environment.get_tmp_dir (), "opus-language-provider-test-%u".printf (Random.next_int ()));
        add_package ("ruby", """{ "name": "ruby", "title": "Ruby", "file-types": ["rb"], "grammar": { "repository": "r", "rev": "abc" } }""");
        add_package ("cpp", """{ "name": "cpp", "title": "C++", "file-types": ["cpp"], "grammar": { "repository": "r", "rev": "abc" } }""");
        add_package ("python", """{ "name": "python", "file-types": ["py"], "grammar": { "repository": "r", "rev": "abc" } }""");
        add_package ("ecma", """{ "name": "ecma", "title": "ECMA" }""");
        add_package ("comment", """{ "name": "comment", "title": "Comment", "grammar": { "repository": "r", "rev": "abc" } }""");
        provider = new CommandBar.LanguageProvider (new Syntax.Languages ({ directory }, {}, {}));
    }

    public void add_package (string name, string manifest) {
        string package = Path.build_filename (directory, name);
        DirUtils.create_with_parents (package, 0700);
        try {
            FileUtils.set_contents (Path.build_filename (package, "language.json"), manifest);
        } catch (FileError e) {
            error ("%s", e.message);
        }
    }

    public void open () {
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

    Test.add_func ("/command-bar/language-provider/everything-typed-is-the-filter", () => {
        var scenario = new Scenario ();

        assert_cmpstr (scenario.provider.prefix, CompareOperator.EQ, "");
    });

    Test.add_func ("/command-bar/language-provider/the-input-asks-for-a-language", () => {
        var scenario = new Scenario ();

        assert_cmpstr (scenario.provider.placeholder, CompareOperator.EQ, "Select language...");
    });

    Test.add_func ("/command-bar/language-provider/languages-a-file-can-be-are-listed-by-title", () => {
        var scenario = new Scenario ();

        scenario.open ();

        assert_cmpstrv (scenario.ids (), { "cpp", "python", "ruby" });
    });

    Test.add_func ("/command-bar/language-provider/a-row-shows-the-title-and-the-name-beside-it", () => {
        var scenario = new Scenario ();

        scenario.open ();

        assert_cmpstr (scenario.picker.items[0].label, CompareOperator.EQ, "C++");
        assert_cmpstr (scenario.picker.items[0].description, CompareOperator.EQ, "cpp");
    });

    Test.add_func ("/command-bar/language-provider/a-language-without-a-title-shows-its-name-once", () => {
        var scenario = new Scenario ();

        scenario.open ();

        assert_cmpstr (scenario.picker.items[1].label, CompareOperator.EQ, "python");
        assert_null (scenario.picker.items[1].description);
    });

    Test.add_func ("/command-bar/language-provider/typing-narrows-the-languages", () => {
        var scenario = new Scenario ();
        scenario.open ();

        scenario.picker.text = "ru";

        assert_cmpstrv (scenario.ids (), { "ruby" });
    });

    Test.add_func ("/command-bar/language-provider/accepting-hands-back-the-packages-name", () => {
        var scenario = new Scenario ();
        scenario.open ();
        scenario.picker.text = "c+";
        string? accepted = null;
        scenario.picker.accepted.connect ((item) => accepted = item.id);

        scenario.picker.accept ();

        assert_cmpstr (accepted, CompareOperator.EQ, "cpp");
    });

    Test.add_func ("/command-bar/language-provider/auto-detect-is-not-offered-unless-asked-for", () => {
        var scenario = new Scenario ();

        scenario.open ();

        assert_false (CommandBar.LanguageProvider.AUTO_DETECT in scenario.ids ());
    });

    Test.add_func ("/command-bar/language-provider/auto-detect-comes-first-when-offered", () => {
        var scenario = new Scenario ();
        scenario.provider.offers_auto_detect = true;

        scenario.open ();

        assert_cmpstr (scenario.picker.items[0].id, CompareOperator.EQ, CommandBar.LanguageProvider.AUTO_DETECT);
        assert_cmpstr (scenario.picker.items[0].label, CompareOperator.EQ, "Auto Detect");
        assert_cmpuint (scenario.picker.items.length, CompareOperator.EQ, 4);
    });

    Test.add_func ("/command-bar/language-provider/with-no-document-nothing-is-listed", () => {
        var scenario = new Scenario ();
        scenario.provider.has_document = false;

        scenario.open ();

        assert_cmpuint (scenario.picker.items.length, CompareOperator.EQ, 0);
    });

    Test.add_func ("/command-bar/language-provider/with-no-document-the-list-says-to-open-a-file", () => {
        var scenario = new Scenario ();
        scenario.provider.has_document = false;

        scenario.open ();

        assert_cmpstr (scenario.picker.empty_message, CompareOperator.EQ, "Open a file to set its language");
    });

    Test.add_func ("/command-bar/language-provider/with-no-document-typing-lists-nothing-either", () => {
        var scenario = new Scenario ();
        scenario.provider.has_document = false;
        scenario.open ();

        scenario.picker.text = "ruby";

        assert_cmpuint (scenario.picker.items.length, CompareOperator.EQ, 0);
        assert_cmpstr (scenario.picker.empty_message, CompareOperator.EQ, "Open a file to set its language");
    });

    Test.add_func ("/command-bar/language-provider/auto-detect-is-not-offered-with-no-document", () => {
        var scenario = new Scenario ();
        scenario.provider.has_document = false;
        scenario.provider.offers_auto_detect = true;

        scenario.open ();

        assert_cmpuint (scenario.picker.items.length, CompareOperator.EQ, 0);
    });

    Test.add_func ("/command-bar/language-provider/nothing-matching-leaves-a-message-instead-of-rows", () => {
        var scenario = new Scenario ();
        scenario.open ();

        scenario.picker.text = "zzz";

        assert_cmpuint (scenario.picker.items.length, CompareOperator.EQ, 0);
        assert_cmpstr (scenario.picker.empty_message, CompareOperator.EQ, "No matching languages");
    });

    return Test.run ();
}
