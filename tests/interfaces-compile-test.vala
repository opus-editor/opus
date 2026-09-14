int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/interfaces/fakes-implement-contracts", () => {
        var tree_view = new FakeFileTreeView ();
        var root = new FileNode ("/tmp", "tmp", true);
        tree_view.populate (root);
        assert (tree_view.populated_root == root);
        tree_view.select_path ("/tmp/a.txt");
        assert (tree_view.selected_path == "/tmp/a.txt");

        var tab_bar_view = new FakeTabBarView ();
        tab_bar_view.add_tab ("/tmp/a.txt", "a.txt", true);
        assert (tab_bar_view.open_paths.length == 1);
        tab_bar_view.mark_modified ("/tmp/a.txt", true);
        assert (tab_bar_view.modified_flags["/tmp/a.txt"] == true);

        var editor_view = new FakeEditorView ();
        editor_view.set_text ("hello");
        assert (editor_view.get_text () == "hello");
        editor_view.set_placeholder ("This file can't be displayed.");
        assert (editor_view.showing_placeholder);
    });

    return Test.run ();
}
