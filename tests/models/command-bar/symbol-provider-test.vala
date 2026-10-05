// The symbols are handed over as the host would: read once, when the
// bar opens. No language is involved — finding them is SyntaxDocument's.

private class Scenario {
    public CommandBar.SymbolProvider provider;
    public CommandBar.Picker picker;
    public bool has_document = true;
    public bool listable = true;
    public bool ready = true;
    public int caret_line = 1;
    public Syntax.Symbol[] symbols = {
        new Syntax.Symbol ("Cart", "class", 1, 6, 1, 12),
        new Syntax.Symbol ("total", "method", 2, 6, 2, 5, "Cart"),
        new Syntax.Symbol ("clear", "method", 7, 6, 7, 11, "Cart"),
        new Syntax.Symbol ("greet", "method", 14, 4, 14, 16)
    };

    public Scenario () {
        provider = new CommandBar.SymbolProvider (() => {
            return has_document ? new CommandBar.DocumentSymbols (symbols, listable, ready, caret_line) : null;
        });
    }

    public void open () {
        picker = new CommandBar.Picker (provider.prefix);
        provider.provide (picker, new Cancellable ());
    }

    public string[] labels () {
        string[] labels = {};
        foreach (var item in picker.items) {
            labels += item.label;
        }
        return labels;
    }
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/command-bar/symbol-provider/a-hash-leads-to-the-symbols", () => {
        var scenario = new Scenario ();

        assert_cmpstr (scenario.provider.prefix, CompareOperator.EQ, "#");
    });

    Test.add_func ("/command-bar/symbol-provider/nothing-typed-lists-every-symbol-in-the-order-of-the-file", () => {
        var scenario = new Scenario ();

        scenario.open ();

        assert_cmpstrv (scenario.labels (), { "Cart", "total", "clear", "greet" });
    });

    Test.add_func ("/command-bar/symbol-provider/a-row-says-what-kind-of-symbol-it-is", () => {
        var scenario = new Scenario ();

        scenario.open ();

        assert_cmpstr (scenario.picker.items[0].description, CompareOperator.EQ, "class");
    });

    Test.add_func ("/command-bar/symbol-provider/a-row-says-what-its-symbol-is-inside-of", () => {
        var scenario = new Scenario ();

        scenario.open ();

        assert_cmpstr (scenario.picker.items[1].description, CompareOperator.EQ, "method · Cart");
    });

    Test.add_func ("/command-bar/symbol-provider/a-row-stands-for-where-its-name-is", () => {
        var scenario = new Scenario ();
        scenario.open ();

        int line, column;
        CommandBar.SymbolProvider.decode (scenario.picker.items[2].id, out line, out column);

        assert_cmpint (line, CompareOperator.EQ, 7);
        assert_cmpint (column, CompareOperator.EQ, 6);
    });

    Test.add_func ("/command-bar/symbol-provider/the-list-starts-on-the-symbol-the-caret-is-in", () => {
        var scenario = new Scenario ();
        scenario.caret_line = 15;

        scenario.open ();

        assert_cmpint (scenario.picker.active_index, CompareOperator.EQ, 3);
    });

    Test.add_func ("/command-bar/symbol-provider/inside-nested-symbols-the-list-starts-on-the-innermost", () => {
        var scenario = new Scenario ();
        scenario.caret_line = 9;

        scenario.open ();

        assert_cmpint (scenario.picker.active_index, CompareOperator.EQ, 2);
    });

    Test.add_func ("/command-bar/symbol-provider/with-the-caret-in-no-symbol-the-list-starts-at-the-top", () => {
        var scenario = new Scenario ();
        scenario.caret_line = 13;

        scenario.open ();

        assert_cmpint (scenario.picker.active_index, CompareOperator.EQ, 0);
    });

    Test.add_func ("/command-bar/symbol-provider/typing-narrows-the-symbols-by-name", () => {
        var scenario = new Scenario ();
        scenario.open ();

        scenario.picker.text = "#tot";

        assert_cmpstrv (scenario.labels (), { "total" });
    });

    Test.add_func ("/command-bar/symbol-provider/typing-matches-loosely", () => {
        var scenario = new Scenario ();
        scenario.open ();

        scenario.picker.text = "#grt";

        assert_cmpstrv (scenario.labels (), { "greet" });
    });

    Test.add_func ("/command-bar/symbol-provider/a-match-carries-the-stretch-that-matched", () => {
        var scenario = new Scenario ();
        scenario.open ();

        scenario.picker.text = "#tot";

        int[] highlights = scenario.picker.items[0].label_highlights;
        assert_cmpint (highlights.length, CompareOperator.EQ, 2);
        assert_cmpint (highlights[0], CompareOperator.EQ, 0);
        assert_cmpint (highlights[1], CompareOperator.EQ, 3);
    });

    Test.add_func ("/command-bar/symbol-provider/a-narrowed-list-starts-on-its-best-match", () => {
        var scenario = new Scenario ();
        scenario.caret_line = 15;
        scenario.open ();

        scenario.picker.text = "#c";

        assert_cmpint (scenario.picker.active_index, CompareOperator.EQ, 0);
    });

    Test.add_func ("/command-bar/symbol-provider/erasing-what-was-typed-brings-every-symbol-back", () => {
        var scenario = new Scenario ();
        scenario.open ();
        scenario.picker.text = "#tot";

        scenario.picker.text = "#";

        assert_cmpstrv (scenario.labels (), { "Cart", "total", "clear", "greet" });
    });

    Test.add_func ("/command-bar/symbol-provider/nothing-matching-leaves-a-message-instead-of-rows", () => {
        var scenario = new Scenario ();
        scenario.open ();

        scenario.picker.text = "#zzz";

        assert_cmpuint (scenario.picker.items.length, CompareOperator.EQ, 0);
        assert_cmpstr (scenario.picker.empty_message, CompareOperator.EQ, "No matching symbols");
    });

    Test.add_func ("/command-bar/symbol-provider/with-no-document-the-list-says-to-open-a-file", () => {
        var scenario = new Scenario ();
        scenario.has_document = false;

        scenario.open ();

        assert_cmpuint (scenario.picker.items.length, CompareOperator.EQ, 0);
        assert_cmpstr (scenario.picker.empty_message, CompareOperator.EQ, "Open a file to go to a symbol");
    });

    Test.add_func ("/command-bar/symbol-provider/a-language-that-cannot-list-symbols-says-so", () => {
        var scenario = new Scenario ();
        scenario.listable = false;
        scenario.symbols = {};

        scenario.open ();

        assert_cmpuint (scenario.picker.items.length, CompareOperator.EQ, 0);
        assert_cmpstr (scenario.picker.empty_message, CompareOperator.EQ, "No symbols for this language");
    });

    Test.add_func ("/command-bar/symbol-provider/a-file-defining-nothing-says-so", () => {
        var scenario = new Scenario ();
        scenario.symbols = {};

        scenario.open ();

        assert_cmpstr (scenario.picker.empty_message, CompareOperator.EQ, "No symbols in this file");
    });

    Test.add_func ("/command-bar/symbol-provider/a-file-still-being-read-says-so", () => {
        var scenario = new Scenario ();
        scenario.ready = false;
        scenario.symbols = {};

        scenario.open ();

        assert_cmpuint (scenario.picker.items.length, CompareOperator.EQ, 0);
        assert_cmpstr (scenario.picker.empty_message, CompareOperator.EQ, "Still reading this file");
    });

    Test.add_func ("/command-bar/symbol-provider/the-symbols-are-read-again-each-time-the-bar-opens", () => {
        var scenario = new Scenario ();
        scenario.open ();
        scenario.picker.close ();
        scenario.symbols = { new Syntax.Symbol ("later", "method", 1, 4, 1, 2) };

        scenario.open ();

        assert_cmpstrv (scenario.labels (), { "later" });
    });

    return Test.run ();
}
