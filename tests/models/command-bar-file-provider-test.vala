// Same tmpdir-fixture pattern as file-tree-test.vala. Layout:
//
//   <root>/
//     src/
//       App.vala
//       models/
//         file-tree.vala
//     README.md
private string make_fixture () throws Error {
    var root_path = DirUtils.make_tmp ("opus-file-provider-test-XXXXXX");
    DirUtils.create (Path.build_filename (root_path, "src"), 0755);
    FileUtils.set_contents (Path.build_filename (root_path, "src", "App.vala"), "");
    DirUtils.create (Path.build_filename (root_path, "src", "models"), 0755);
    FileUtils.set_contents (Path.build_filename (root_path, "src", "models", "file-tree.vala"), "");
    FileUtils.set_contents (Path.build_filename (root_path, "README.md"), "");
    return root_path;
}

private void remove_recursive (string path) {
    if (FileUtils.test (path, FileTest.IS_DIR)) {
        Dir dir;
        try {
            dir = Dir.open (path);
        } catch (Error e) {
            return;
        }
        string? entry;
        while ((entry = dir.read_name ()) != null) {
            remove_recursive (Path.build_filename (path, entry));
        }
        DirUtils.remove (path);
    } else {
        FileUtils.remove (path);
    }
}

private class Scenario {
    public string root_path;
    public WorkspaceContext context;
    public CommandBar.RecentFiles recent;
    public CommandBar.FileProvider provider;
    public CommandBar.Picker picker;

    public Scenario () throws Error {
        root_path = make_fixture ();
        context = new WorkspaceContext (root_path);
        recent = new CommandBar.RecentFiles ();
        provider = new CommandBar.FileProvider (context, recent);
        provider.activate ();
        picker = new CommandBar.Picker ("");
    }

    /** Hands the picker to the provider and waits for its first walk to finish — `busy` dropping back to false is how the picker itself learns that. */
    public void provide_and_wait () {
        provider.provide (picker, new Cancellable ());
        wait_until (() => !picker.busy);
    }

    public string absolute (string relative) {
        return Path.build_filename (root_path, relative);
    }

    public void close () {
        provider.deactivate ();
        remove_recursive (root_path);
    }
}

private delegate bool Condition ();

private void wait_until (Condition condition) {
    var loop = new MainLoop ();
    uint waited = 0;
    Timeout.add (10, () => {
        waited += 10;
        if (condition () || waited > 5000) {
            loop.quit ();
            return Source.REMOVE;
        }
        return Source.CONTINUE;
    });
    loop.run ();
    assert_true (condition ());
}

private string[] ids_of (CommandBar.Picker picker) {
    var ids = new string[picker.items.length];
    for (uint i = 0; i < picker.items.length; i++) {
        ids[i] = picker.items[i].id;
    }
    return ids;
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/command-bar/file-provider/typed-filter-ranks-matching-files-with-split-highlights", () => {
        Scenario? scenario = null;
        try {
            scenario = new Scenario ();
            scenario.provide_and_wait ();

            scenario.picker.text = "filetree";

            var ids = ids_of (scenario.picker);
            assert_cmpint (ids.length, CompareOperator.EQ, 1);
            assert_cmpstr (ids[0], CompareOperator.EQ, scenario.absolute ("src/models/file-tree.vala"));
            var item = scenario.picker.items[0];
            assert_cmpstr (item.label, CompareOperator.EQ, "file-tree.vala");
            assert_cmpstr (item.description, CompareOperator.EQ, "src/models");
            assert_cmpstr (item.separator_label, CompareOperator.EQ, "files");
            assert_cmpint (item.label_highlights.length, CompareOperator.EQ, 4);
            assert_cmpint (item.description_highlights.length, CompareOperator.EQ, 0);
        } catch (Error e) {
            assert_not_reached ();
        } finally {
            scenario?.close ();
        }
    });

    Test.add_func ("/command-bar/file-provider/empty-filter-lists-recent-files-most-recent-first", () => {
        Scenario? scenario = null;
        try {
            scenario = new Scenario ();
            scenario.recent.push (scenario.absolute ("README.md"));
            scenario.recent.push (scenario.absolute ("src/App.vala"));

            scenario.provide_and_wait ();

            var ids = ids_of (scenario.picker);
            assert_cmpint (ids.length, CompareOperator.EQ, 2);
            assert_cmpstr (ids[0], CompareOperator.EQ, scenario.absolute ("src/App.vala"));
            assert_cmpstr (ids[1], CompareOperator.EQ, scenario.absolute ("README.md"));
            assert_cmpstr (scenario.picker.items[0].separator_label, CompareOperator.EQ, "recently opened");
            assert_null (scenario.picker.items[1].separator_label);
            assert_cmpstr (scenario.picker.items[0].description, CompareOperator.EQ, "src");
            assert_null (scenario.picker.items[1].description);
        } catch (Error e) {
            assert_not_reached ();
        } finally {
            scenario?.close ();
        }
    });

    Test.add_func ("/command-bar/file-provider/empty-filter-with-nothing-recent-lists-nothing", () => {
        Scenario? scenario = null;
        try {
            scenario = new Scenario ();

            scenario.provide_and_wait ();

            assert_cmpuint (scenario.picker.items.length, CompareOperator.EQ, 0);
        } catch (Error e) {
            assert_not_reached ();
        } finally {
            scenario?.close ();
        }
    });

    Test.add_func ("/command-bar/file-provider/recent-match-comes-first-and-is-not-repeated-in-files", () => {
        Scenario? scenario = null;
        try {
            scenario = new Scenario ();
            scenario.recent.push (scenario.absolute ("src/models/file-tree.vala"));
            scenario.provide_and_wait ();

            scenario.picker.text = "vala";

            var ids = ids_of (scenario.picker);
            assert_cmpint (ids.length, CompareOperator.EQ, 2);
            assert_cmpstr (ids[0], CompareOperator.EQ, scenario.absolute ("src/models/file-tree.vala"));
            assert_cmpstr (scenario.picker.items[0].separator_label, CompareOperator.EQ, "recently opened");
            assert_cmpstr (ids[1], CompareOperator.EQ, scenario.absolute ("src/App.vala"));
            assert_cmpstr (scenario.picker.items[1].separator_label, CompareOperator.EQ, "files");
        } catch (Error e) {
            assert_not_reached ();
        } finally {
            scenario?.close ();
        }
    });

    Test.add_func ("/command-bar/file-provider/recent-files-match-on-name-only", () => {
        Scenario? scenario = null;
        try {
            scenario = new Scenario ();
            scenario.recent.push (scenario.absolute ("src/App.vala"));
            scenario.provide_and_wait ();

            scenario.picker.text = "models";

            var ids = ids_of (scenario.picker);
            assert_cmpint (ids.length, CompareOperator.EQ, 1);
            assert_cmpstr (ids[0], CompareOperator.EQ, scenario.absolute ("src/models/file-tree.vala"));
        } catch (Error e) {
            assert_not_reached ();
        } finally {
            scenario?.close ();
        }
    });

    Test.add_func ("/command-bar/file-provider/no-match-lists-nothing", () => {
        Scenario? scenario = null;
        try {
            scenario = new Scenario ();
            scenario.provide_and_wait ();

            scenario.picker.text = "zzz";

            assert_cmpuint (scenario.picker.items.length, CompareOperator.EQ, 0);
        } catch (Error e) {
            assert_not_reached ();
        } finally {
            scenario?.close ();
        }
    });

    Test.add_func ("/command-bar/file-provider/accepting-an-item-records-it-as-recent", () => {
        Scenario? scenario = null;
        try {
            scenario = new Scenario ();
            scenario.provide_and_wait ();
            scenario.picker.text = "readme";

            scenario.picker.accept ();

            assert_true (scenario.recent.contains (scenario.absolute ("README.md")));
        } catch (Error e) {
            assert_not_reached ();
        } finally {
            scenario?.close ();
        }
    });

    Test.add_func ("/command-bar/file-provider/typing-while-the-walk-is-cold-still-answers-once-warm", () => {
        Scenario? scenario = null;
        try {
            scenario = new Scenario ();
            scenario.picker.text = "app";

            scenario.provide_and_wait ();

            var ids = ids_of (scenario.picker);
            assert_cmpint (ids.length, CompareOperator.EQ, 1);
            assert_cmpstr (ids[0], CompareOperator.EQ, scenario.absolute ("src/App.vala"));
        } catch (Error e) {
            assert_not_reached ();
        } finally {
            scenario?.close ();
        }
    });

    Test.add_func ("/command-bar/file-provider/a-changed-directory-is-refreshed-in-place", () => {
        Scenario? scenario = null;
        try {
            scenario = new Scenario ();
            scenario.provide_and_wait ();
            FileUtils.set_contents (scenario.absolute ("src/New.vala"), "");
            FileUtils.remove (scenario.absolute ("src/App.vala"));

            scenario.context.directory_changed (scenario.absolute ("src"));
            scenario.picker.text = "vala";

            var ids = ids_of (scenario.picker);
            assert_cmpint (ids.length, CompareOperator.EQ, 2);
            assert_cmpstr (ids[0], CompareOperator.EQ, scenario.absolute ("src/New.vala"));
            assert_cmpstr (ids[1], CompareOperator.EQ, scenario.absolute ("src/models/file-tree.vala"));
        } catch (Error e) {
            assert_not_reached ();
        } finally {
            scenario?.close ();
        }
    });

    Test.add_func ("/command-bar/file-provider/a-second-opening-answers-from-the-previous-list-right-away", () => {
        Scenario? scenario = null;
        try {
            scenario = new Scenario ();
            scenario.provide_and_wait ();
            scenario.picker.close ();
            var second = new CommandBar.Picker ("");

            scenario.provider.provide (second, new Cancellable ());
            second.text = "readme";

            assert_cmpuint (second.items.length, CompareOperator.EQ, 1);
            wait_until (() => !second.busy);
        } catch (Error e) {
            assert_not_reached ();
        } finally {
            scenario?.close ();
        }
    });

    return Test.run ();
}
