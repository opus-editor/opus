private class RecordingProvider : Object, IWorkspaceExtension, CommandBar.IProvider {
    public WorkspaceContext context { get; set; }
    private string _prefix;
    public string prefix { owned get { return _prefix; } }
    public string placeholder { owned get { return "placeholder for " + _prefix; } }

    public int provide_count = 0;
    public CommandBar.Picker? last_picker = null;
    public Cancellable? last_cancellable = null;

    public RecordingProvider (string prefix) {
        _prefix = prefix;
    }

    public void activate () {}
    public void deactivate () {}

    public void provide (CommandBar.Picker picker, Cancellable cancellable) {
        provide_count++;
        last_picker = picker;
        last_cancellable = cancellable;
    }
}

private CommandBar.Registry registry_with (RecordingProvider files, RecordingProvider commands) {
    var registry = new CommandBar.Registry ();
    registry.add (files);
    registry.add (commands);
    return registry;
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/command-bar/router/open-hands-a-picker-to-the-default-provider", () => {
        var files = new RecordingProvider ("");
        var commands = new RecordingProvider (">");
        var router = new CommandBar.Router (registry_with (files, commands));
        CommandBar.Picker? announced = null;
        router.opened.connect ((picker) => announced = picker);

        router.open ();

        assert_true (router.is_open);
        assert_cmpint (files.provide_count, CompareOperator.EQ, 1);
        assert_cmpint (commands.provide_count, CompareOperator.EQ, 0);
        assert_true (announced == files.last_picker);
        assert_cmpstr (announced.placeholder, CompareOperator.EQ, "placeholder for ");
    });

    Test.add_func ("/command-bar/router/opening-with-a-prefixed-text-starts-on-that-provider", () => {
        var files = new RecordingProvider ("");
        var commands = new RecordingProvider (">");
        var router = new CommandBar.Router (registry_with (files, commands));

        router.open (">sav");

        assert_cmpint (commands.provide_count, CompareOperator.EQ, 1);
        assert_cmpstr (commands.last_picker.filter, CompareOperator.EQ, "sav");
    });

    Test.add_func ("/command-bar/router/typing-a-prefix-switches-provider-and-keeps-the-text", () => {
        var files = new RecordingProvider ("");
        var commands = new RecordingProvider (">");
        var router = new CommandBar.Router (registry_with (files, commands));
        router.open ();
        var first_picker = files.last_picker;
        int opened = 0;
        router.opened.connect (() => opened++);

        first_picker.text = ">";

        assert_true (first_picker.is_closed);
        assert_true (files.last_cancellable.is_cancelled ());
        assert_cmpint (commands.provide_count, CompareOperator.EQ, 1);
        assert_cmpstr (commands.last_picker.text, CompareOperator.EQ, ">");
        assert_cmpstr (commands.last_picker.filter, CompareOperator.EQ, "");
        assert_cmpint (opened, CompareOperator.EQ, 1);
        assert_true (router.is_open);
    });

    Test.add_func ("/command-bar/router/deleting-the-prefix-switches-back", () => {
        var files = new RecordingProvider ("");
        var commands = new RecordingProvider (">");
        var router = new CommandBar.Router (registry_with (files, commands));
        router.open (">x");

        commands.last_picker.text = "x";

        assert_cmpint (files.provide_count, CompareOperator.EQ, 1);
        assert_cmpstr (files.last_picker.filter, CompareOperator.EQ, "x");
    });

    Test.add_func ("/command-bar/router/text-within-the-same-provider-does-not-reprovide", () => {
        var files = new RecordingProvider ("");
        var commands = new RecordingProvider (">");
        var router = new CommandBar.Router (registry_with (files, commands));
        router.open ();

        files.last_picker.text = "abc";
        files.last_picker.text = "abcd";

        assert_cmpint (files.provide_count, CompareOperator.EQ, 1);
    });

    Test.add_func ("/command-bar/router/close-cancels-then-closes-the-picker", () => {
        var files = new RecordingProvider ("");
        var commands = new RecordingProvider (">");
        var router = new CommandBar.Router (registry_with (files, commands));
        router.open ();
        int closed = 0;
        router.closed.connect (() => closed++);

        router.close ();

        assert_false (router.is_open);
        assert_true (files.last_cancellable.is_cancelled ());
        assert_true (files.last_picker.is_closed);
        assert_cmpint (closed, CompareOperator.EQ, 1);
    });

    Test.add_func ("/command-bar/router/open-while-open-and-close-while-closed-are-no-ops", () => {
        var files = new RecordingProvider ("");
        var commands = new RecordingProvider (">");
        var router = new CommandBar.Router (registry_with (files, commands));
        int closed = 0;
        router.closed.connect (() => closed++);

        router.close ();
        router.open ();
        router.open ("other");

        assert_cmpint (files.provide_count, CompareOperator.EQ, 1);
        assert_cmpint (closed, CompareOperator.EQ, 0);
    });

    Test.add_func ("/command-bar/router/empty-registry-never-opens", () => {
        var router = new CommandBar.Router (new CommandBar.Registry ());
        bool opened = false;
        router.opened.connect (() => opened = true);

        router.open ();

        assert_false (router.is_open);
        assert_false (opened);
    });

    return Test.run ();
}
