private string make_folder () {
    try {
        return DirUtils.make_tmp ("opus-last-folder-test-XXXXXX");
    } catch (Error e) {
        error ("failed to create fixture directory: %s", e.message);
    }
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/last-folder/gives-the-recorded-folder", () => {
        var folder = make_folder ();
        var last_folder = new LastFolder (true, folder);

        var pathname = last_folder.get_pathname ();

        assert (pathname == folder);
        DirUtils.remove (folder);
    });

    Test.add_func ("/last-folder/gives-nothing-when-nothing-is-recorded", () => {
        var last_folder = new LastFolder (true, null);

        var pathname = last_folder.get_pathname ();

        assert (pathname == null);
    });

    Test.add_func ("/last-folder/gives-nothing-when-the-recorded-folder-is-gone", () => {
        var folder = make_folder ();
        DirUtils.remove (folder);
        var last_folder = new LastFolder (true, folder);

        var pathname = last_folder.get_pathname ();

        assert (pathname == null);
    });

    Test.add_func ("/last-folder/gives-nothing-when-the-setting-is-off", () => {
        var folder = make_folder ();
        var last_folder = new LastFolder (false, folder);

        var pathname = last_folder.get_pathname ();

        assert (pathname == null);
        DirUtils.remove (folder);
    });

    Test.add_func ("/last-folder/drops-a-leftover-record-when-the-setting-is-off", () => {
        var last_folder = new LastFolder (false, "/some/folder");

        assert (last_folder.recorded_pathname == null);
    });

    Test.add_func ("/last-folder/records-a-folder-while-on", () => {
        var last_folder = new LastFolder (true, null);

        last_folder.record ("/some/folder");

        assert (last_folder.recorded_pathname == "/some/folder");
    });

    Test.add_func ("/last-folder/records-the-latest-folder", () => {
        var last_folder = new LastFolder (true, "/first/folder");

        last_folder.record ("/second/folder");

        assert (last_folder.recorded_pathname == "/second/folder");
    });

    Test.add_func ("/last-folder/does-not-record-a-folder-while-off", () => {
        var last_folder = new LastFolder (false, null);

        last_folder.record ("/some/folder");

        assert (last_folder.recorded_pathname == null);
    });

    Test.add_func ("/last-folder/clearing-drops-the-record", () => {
        var last_folder = new LastFolder (true, "/some/folder");

        last_folder.clear ();

        assert (last_folder.recorded_pathname == null);
    });

    Test.add_func ("/last-folder/turning-on-records-the-folder-linked-right-now", () => {
        var last_folder = new LastFolder (false, null);

        last_folder.apply_setting (true, "/some/folder");

        assert (last_folder.recorded_pathname == "/some/folder");
    });

    Test.add_func ("/last-folder/turning-on-with-no-folder-linked-records-nothing", () => {
        var last_folder = new LastFolder (false, null);

        last_folder.apply_setting (true, null);

        assert (last_folder.recorded_pathname == null);
    });

    Test.add_func ("/last-folder/turning-off-drops-the-record", () => {
        var last_folder = new LastFolder (true, "/some/folder");

        last_folder.apply_setting (false, "/some/folder");

        assert (last_folder.recorded_pathname == null);
    });

    Test.add_func ("/last-folder/an-unchanged-setting-keeps-the-record", () => {
        var last_folder = new LastFolder (true, "/some/folder");

        last_folder.apply_setting (true, "/another/folder");

        assert (last_folder.recorded_pathname == "/some/folder");
    });

    Test.add_func ("/last-folder/records-folders-after-being-turned-on", () => {
        var last_folder = new LastFolder (false, null);
        last_folder.apply_setting (true, null);

        last_folder.record ("/some/folder");

        assert (last_folder.recorded_pathname == "/some/folder");
    });

    return Test.run ();
}
