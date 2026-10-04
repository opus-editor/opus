int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/command-bar/recent-files/most-recent-comes-first", () => {
        var recent = new CommandBar.RecentFiles ();

        recent.push ("/a");
        recent.push ("/b");

        var all = recent.all ();
        assert_cmpint (all.length, CompareOperator.EQ, 2);
        assert_cmpstr (all[0], CompareOperator.EQ, "/b");
        assert_cmpstr (all[1], CompareOperator.EQ, "/a");
    });

    Test.add_func ("/command-bar/recent-files/pushing-again-moves-to-the-front-without-duplicating", () => {
        var recent = new CommandBar.RecentFiles ();
        recent.push ("/a");
        recent.push ("/b");

        recent.push ("/a");

        var all = recent.all ();
        assert_cmpint (all.length, CompareOperator.EQ, 2);
        assert_cmpstr (all[0], CompareOperator.EQ, "/a");
    });

    Test.add_func ("/command-bar/recent-files/remove-drops-the-path", () => {
        var recent = new CommandBar.RecentFiles ();
        recent.push ("/a");
        recent.push ("/b");

        recent.remove ("/a");

        assert_false (recent.contains ("/a"));
        assert_cmpuint (recent.size, CompareOperator.EQ, 1);
    });

    Test.add_func ("/command-bar/recent-files/removing-an-unknown-path-does-not-fire-changed", () => {
        var recent = new CommandBar.RecentFiles ();
        int changes = 0;
        recent.changed.connect (() => changes++);

        recent.remove ("/missing");

        assert_cmpint (changes, CompareOperator.EQ, 0);
    });

    Test.add_func ("/command-bar/recent-files/empty-list", () => {
        var recent = new CommandBar.RecentFiles ();

        assert_cmpint (recent.all ().length, CompareOperator.EQ, 0);
        assert_false (recent.contains ("/a"));
    });

    Test.add_func ("/command-bar/recent-files/oldest-falls-off-past-the-cap", () => {
        var recent = new CommandBar.RecentFiles ();

        for (uint i = 0; i <= CommandBar.RecentFiles.MAX; i++) {
            recent.push ("/file-%u".printf (i));
        }

        assert_cmpuint (recent.size, CompareOperator.EQ, CommandBar.RecentFiles.MAX);
        assert_false (recent.contains ("/file-0"));
        assert_true (recent.contains ("/file-1"));
    });

    Test.add_func ("/command-bar/recent-files/push-fires-changed", () => {
        var recent = new CommandBar.RecentFiles ();
        int changes = 0;
        recent.changed.connect (() => changes++);

        recent.push ("/a");

        assert_cmpint (changes, CompareOperator.EQ, 1);
    });

    return Test.run ();
}
