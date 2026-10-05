// Guards languages/ itself rather than a Model: every bundled package
// must load, and each of its queries must compile against its own
// grammar using only predicates Opus implements. OPUS_LANGUAGES_DIR
// and OPUS_GRAMMARS_DIR are set by tests/meson.build.

private const string[] QUERY_NAMES = { "highlights", "injections", "locals", "indents", "tags" };

private GenericArray<Syntax.LanguagePackage> bundled_packages () {
    string languages = Environment.get_variable ("OPUS_LANGUAGES_DIR");
    var packages = new GenericArray<Syntax.LanguagePackage> ();
    try {
        var dir = Dir.open (languages);
        string? name;
        while ((name = dir.read_name ()) != null) {
            string directory = Path.build_filename (languages, name);
            if (FileUtils.test (directory, FileTest.IS_DIR)) {
                packages.add (Syntax.LanguagePackage.load (directory));
            }
        }
    } catch (Error e) {
        error ("%s", e.message);
    }
    return packages;
}

private void test_every_bundled_package_loads () {
    var packages = bundled_packages ();

    assert_cmpuint (packages.length, CompareOperator.GT, 0);
}

private void test_every_bundled_query_compiles_against_its_grammar () {
    var packages = bundled_packages ();
    var loader = new Syntax.GrammarLoader ({ Environment.get_variable ("OPUS_GRAMMARS_DIR") });
    var source = new Syntax.QuerySource (new Syntax.LanguageRegistry ({ Environment.get_variable ("OPUS_LANGUAGES_DIR") }));

    foreach (var package in packages) {
        if (package.grammar == null) {
            continue;
        }
        foreach (unowned string query_name in QUERY_NAMES) {
            var text = source.read (package.name, query_name);
            if (text == null) {
                continue;
            }
            try {
                var query = Syntax.QuerySource.compile (loader.load (package.grammar), text);
                new Syntax.QueryPredicates (query);
            } catch (Error e) {
                error ("%s/%s: %s", package.name, query_name, e.message);
            }
        }
    }
}

void main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/languages/every_bundled_package_loads", test_every_bundled_package_loads);
    Test.add_func ("/languages/every_bundled_query_compiles_against_its_grammar", test_every_bundled_query_compiles_against_its_grammar);
    Test.run ();
}
