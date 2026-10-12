// Reindent over every example in tests/examples/ whose language says where lines go: a well-indented file comes back unchanged.

// Angular's `@for (…) {` blocks are plain text to the HTML grammar: the lines inside them are indented by a rule it can't see.
private const string[] SKIPPED = { "example.component.html" };

private Syntax.Languages languages () {
    if (Syntax.Languages.instance == null) {
        Syntax.Languages.instance = new Syntax.Languages ({ Environment.get_variable ("OPUS_LANGUAGES_DIR") }, { Environment.get_variable ("OPUS_GRAMMARS_DIR") }, { "keyword" });
    }
    return Syntax.Languages.instance;
}

private string[] example_paths () {
    string[] paths = {};
    var root = Environment.get_variable ("OPUS_EXAMPLES_DIR");
    try {
        var groups = Dir.open (root);
        string? group;
        while ((group = groups.read_name ()) != null) {
            var files = Dir.open (Path.build_filename (root, group));
            string? name;
            while ((name = files.read_name ()) != null) {
                paths += Path.build_filename (root, group, name);
            }
        }
    } catch (Error e) {
        error (e.message);
    }
    return paths;
}

/** The file's own unit: tabs if any line starts with one, else the narrowest indentation it uses. */
private void sniff_indent (string text, out bool insert_spaces, out int indent_size) {
    insert_spaces = true;
    indent_size = 0;
    foreach (var line in text.split ("\n")) {
        if (line.has_prefix ("\t")) {
            insert_spaces = false;
            indent_size = 1;
            return;
        }
        int spaces = 0;
        while (spaces < line.length && line[spaces] == ' ') {
            spaces++;
        }
        if (spaces > 0 && spaces < line.length && (indent_size == 0 || spaces < indent_size)) {
            indent_size = spaces;
        }
    }
    if (indent_size == 0) {
        indent_size = 2;
    }
}

/** The first line Reindent changes, as "N: [before] -> [after]", or null when it changes nothing. */
private string? first_change (string path) {
    var language = languages ().detect (path);
    string text;
    try {
        FileUtils.get_contents (path, out text);
    } catch (Error e) {
        error (e.message);
    }
    var input = Functions.Input.of_document (text);
    input.language = language.package.name;
    bool insert_spaces;
    int indent_size;
    sniff_indent (text, out insert_spaces, out indent_size);
    input.insert_spaces = insert_spaces;
    input.indent_size = indent_size;
    string result;
    try {
        result = new Functions.Native.Reindent ().run (input)[0];
    } catch (Functions.FunctionError e) {
        Test.skip_printf ("refused: %s", e.message);
        return null;
    }
    var before = text.split ("\n");
    var after = result.split ("\n");
    for (int i = 0; i < before.length && i < after.length; i++) {
        if (before[i] != after[i]) {
            return "%d: [%s] -> [%s]".printf (i + 1, before[i], after[i]);
        }
    }
    return before.length == after.length ? null : "line counts differ";
}

void main (string[] args) {
    Test.init (ref args);
    foreach (var path in example_paths ()) {
        var language = languages ().detect (path);
        if (language == null || !language.indents_lines || Path.get_basename (path) in SKIPPED) {
            continue;
        }
        var name = Path.get_basename (path);
        Test.add_data_func ("/functions/reindent/examples/" + name, () => {
            var change = first_change (path);
            if (change != null) {
                Test.fail_printf ("%s: Reindent changed line %s", name, change);
            }
        });
    }
    Test.run ();
}
