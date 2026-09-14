int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/models/workspace/resolve_root_path/with_arg", () => {
        string root = Workspace.resolve_root_path ({ "codi-gtk", "/home/user/project" }, "/home/user");

        assert (root == "/home/user/project");
    });

    Test.add_func ("/models/workspace/resolve_root_path/without_arg", () => {
        string root = Workspace.resolve_root_path ({ "codi-gtk" }, "/home/user");

        assert (root == "/home/user");
    });

    return Test.run ();
}
