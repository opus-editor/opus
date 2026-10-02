private class FakeProvider : Object, IWorkspaceExtension, CommandBar.IProvider {
    public WorkspaceContext context { get; set; }
    private string _prefix;
    public string prefix { owned get { return _prefix; } }
    public string placeholder { owned get { return "fake"; } }

    public FakeProvider (string prefix) {
        _prefix = prefix;
    }

    public void activate () {}
    public void deactivate () {}
    public void provide (CommandBar.Picker picker, Cancellable cancellable) {}
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/command-bar/registry/resolves-the-prefix-the-text-starts-with", () => {
        var registry = new CommandBar.Registry ();
        var files = new FakeProvider ("");
        var commands = new FakeProvider (">");
        registry.add (files);
        registry.add (commands);

        assert_true (registry.resolve (">open") == commands);
        assert_true (registry.resolve ("open") == files);
    });

    Test.add_func ("/command-bar/registry/empty-text-resolves-to-the-default-provider", () => {
        var registry = new CommandBar.Registry ();
        var files = new FakeProvider ("");
        registry.add (new FakeProvider (">"));
        registry.add (files);

        assert_true (registry.resolve ("") == files);
    });

    Test.add_func ("/command-bar/registry/longest-matching-prefix-wins", () => {
        var registry = new CommandBar.Registry ();
        var short_prefix = new FakeProvider ("ext");
        var long_prefix = new FakeProvider ("ext install");
        registry.add (short_prefix);
        registry.add (long_prefix);

        assert_true (registry.resolve ("ext install foo") == long_prefix);
        assert_true (registry.resolve ("ext foo") == short_prefix);
    });

    Test.add_func ("/command-bar/registry/no-provider-at-all-resolves-to-null", () => {
        var registry = new CommandBar.Registry ();

        assert_null (registry.resolve ("anything"));
    });

    Test.add_func ("/command-bar/registry/unmatched-prefix-without-a-default-resolves-to-null", () => {
        var registry = new CommandBar.Registry ();
        registry.add (new FakeProvider (">"));

        assert_null (registry.resolve ("plain"));
    });

    Test.add_func ("/command-bar/registry/adding-twice-registers-once", () => {
        var registry = new CommandBar.Registry ();
        var files = new FakeProvider ("");
        int changes = 0;
        registry.changed.connect (() => changes++);

        registry.add (files);
        registry.add (files);

        assert_cmpuint (registry.all ().length, CompareOperator.EQ, 1);
        assert_cmpint (changes, CompareOperator.EQ, 1);
    });

    Test.add_func ("/command-bar/registry/removed-provider-no-longer-resolves", () => {
        var registry = new CommandBar.Registry ();
        var commands = new FakeProvider (">");
        registry.add (commands);

        registry.remove (commands);

        assert_null (registry.resolve (">x"));
        assert_cmpuint (registry.all ().length, CompareOperator.EQ, 0);
    });

    return Test.run ();
}
