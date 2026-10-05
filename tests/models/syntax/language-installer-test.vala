private string new_directory () {
    string directory = Path.build_filename (Environment.get_tmp_dir (), "opus-language-installer-test-%u".printf (Random.next_int ()));
    DirUtils.create_with_parents (directory, 0700);
    return directory;
}

private void write_file (string directory, string name, string contents) {
    DirUtils.create_with_parents (directory, 0700);
    try {
        FileUtils.set_contents (Path.build_filename (directory, name), contents);
    } catch (FileError e) {
        error ("%s", e.message);
    }
}

private string read_file (string path) {
    string contents;
    try {
        FileUtils.get_contents (path, out contents);
    } catch (FileError e) {
        error ("%s", e.message);
    }
    return contents;
}

private void test_a_package_is_installed_under_its_language_name () {
    string source = new_directory ();
    string languages = new_directory ();
    write_file (source, "language.json", """{ "name": "ruby" }""");

    Syntax.LanguagePackage? installed = null;
    try {
        installed = new Syntax.LanguageInstaller (languages).install (source);
    } catch (Syntax.InstallError e) {
        error ("%s", e.message);
    }

    assert_cmpstr (installed.name, CompareOperator.EQ, "ruby");
    assert_cmpstr (installed.directory, CompareOperator.EQ, Path.build_filename (languages, "ruby"));
}

private void test_the_queries_are_installed_with_it () {
    string source = new_directory ();
    string languages = new_directory ();
    write_file (source, "language.json", """{ "name": "ruby" }""");
    write_file (Path.build_filename (source, "queries"), "highlights.scm", "(comment) @comment");

    try {
        new Syntax.LanguageInstaller (languages).install (source);
    } catch (Syntax.InstallError e) {
        error ("%s", e.message);
    }

    assert_cmpstr (read_file (Path.build_filename (languages, "ruby", "queries", "highlights.scm")), CompareOperator.EQ, "(comment) @comment");
}

private void test_files_that_are_not_part_of_a_package_stay_behind () {
    string source = new_directory ();
    string languages = new_directory ();
    write_file (source, "language.json", """{ "name": "ruby" }""");
    write_file (source, "README.md", "notes");
    write_file (Path.build_filename (source, "queries"), "notes.txt", "notes");

    try {
        new Syntax.LanguageInstaller (languages).install (source);
    } catch (Syntax.InstallError e) {
        error ("%s", e.message);
    }

    assert_false (FileUtils.test (Path.build_filename (languages, "ruby", "README.md"), FileTest.EXISTS));
    assert_false (FileUtils.test (Path.build_filename (languages, "ruby", "queries", "notes.txt"), FileTest.EXISTS));
}

private void test_installing_again_replaces_the_manifest () {
    string source = new_directory ();
    string languages = new_directory ();
    var installer = new Syntax.LanguageInstaller (languages);
    write_file (source, "language.json", """{ "name": "ruby", "file-types": ["rb"] }""");
    Syntax.LanguagePackage? installed = null;
    try {
        installer.install (source);
        write_file (source, "language.json", """{ "name": "ruby", "file-types": ["rake"] }""");

        installed = installer.install (source);
    } catch (Syntax.InstallError e) {
        error ("%s", e.message);
    }

    assert_cmpstrv (installed.extensions, { "rake" });
}

private void test_installing_again_drops_queries_the_new_version_lacks () {
    string source = new_directory ();
    string languages = new_directory ();
    var installer = new Syntax.LanguageInstaller (languages);
    write_file (source, "language.json", """{ "name": "ruby" }""");
    write_file (Path.build_filename (source, "queries"), "injections.scm", "(comment) @injection.content");
    try {
        installer.install (source);
        FileUtils.remove (Path.build_filename (source, "queries", "injections.scm"));

        installer.install (source);
    } catch (Syntax.InstallError e) {
        error ("%s", e.message);
    }

    assert_false (FileUtils.test (Path.build_filename (languages, "ruby", "queries", "injections.scm"), FileTest.EXISTS));
}

private void test_a_folder_without_a_valid_manifest_is_refused () {
    string source = new_directory ();
    string languages = new_directory ();
    write_file (source, "language.json", """{ "file-types": ["rb"] }""");

    try {
        new Syntax.LanguageInstaller (languages).install (source);
        assert_not_reached ();
    } catch (Syntax.InstallError e) {
        assert_true (e is Syntax.InstallError.INVALID_PACKAGE);
    }
}

private void test_a_refused_package_installs_nothing () {
    string source = new_directory ();
    string languages = new_directory ();
    write_file (source, "language.json", """{ "file-types": ["rb"] }""");

    try {
        new Syntax.LanguageInstaller (languages).install (source);
    } catch (Syntax.InstallError e) {
        // Expected: the test is about what the refusal leaves on disk.
    }

    Dir dir;
    try {
        dir = Dir.open (languages);
    } catch (FileError e) {
        error ("%s", e.message);
    }
    assert_null (dir.read_name ());
}

private void test_a_repository_that_cannot_be_cloned_fails () {
    if (!HostCommand.has_program ("git")) {
        Test.skip ("needs git");
        return;
    }
    string languages = new_directory ();

    try {
        new Syntax.LanguageInstaller (languages).install_from_repository (Path.build_filename (new_directory (), "no-such-repository"));
        assert_not_reached ();
    } catch (Syntax.InstallError e) {
        assert_true (e is Syntax.InstallError.FAILED);
    }
}

void main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/models/syntax/language-installer/a_package_is_installed_under_its_language_name", test_a_package_is_installed_under_its_language_name);
    Test.add_func ("/models/syntax/language-installer/the_queries_are_installed_with_it", test_the_queries_are_installed_with_it);
    Test.add_func ("/models/syntax/language-installer/files_that_are_not_part_of_a_package_stay_behind", test_files_that_are_not_part_of_a_package_stay_behind);
    Test.add_func ("/models/syntax/language-installer/installing_again_replaces_the_manifest", test_installing_again_replaces_the_manifest);
    Test.add_func ("/models/syntax/language-installer/installing_again_drops_queries_the_new_version_lacks", test_installing_again_drops_queries_the_new_version_lacks);
    Test.add_func ("/models/syntax/language-installer/a_folder_without_a_valid_manifest_is_refused", test_a_folder_without_a_valid_manifest_is_refused);
    Test.add_func ("/models/syntax/language-installer/a_refused_package_installs_nothing", test_a_refused_package_installs_nothing);
    Test.add_func ("/models/syntax/language-installer/a_repository_that_cannot_be_cloned_fails", test_a_repository_that_cannot_be_cloned_fails);
    Test.run ();
}
