// Pure in-memory tests — no disk/git involved, unlike git-status's own
// tests: FileDecoration.Registry is git-agnostic, so its own fixtures are
// just a fake provider and plain path strings under a made-up root.

private class FakeProvider : Object, IWorkspaceExtension, FileDecoration.IProvider {
    public WorkspaceContext context { get; set; }
    private HashTable<string, FileDecoration.State> decorations = new HashTable<string, FileDecoration.State> (str_hash, str_equal);

    public FakeProvider (WorkspaceContext context) {
        Object (context: context);
    }

    public void activate () {}
    public void deactivate () {}

    public HashTable<string, FileDecoration.State> current_decorations () {
        return decorations;
    }

    /** `state` null removes `path` entirely — always fires decorations_changed, same as a real provider would after any change to its own set. */
    public void set_decoration (string path, FileDecoration.State? state) {
        if (state == null) {
            decorations.remove (path);
        } else {
            decorations[path] = state;
        }
        decorations_changed ();
    }
}

private const string ROOT = "/root";

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/file-decoration-registry/no-providers-returns-null", () => {
        var registry = new FileDecoration.Registry (ROOT);

        assert (registry.decoration_for (Path.build_filename (ROOT, "a.txt"), false) == null);
    });

    Test.add_func ("/file-decoration-registry/a-files-own-direct-decoration", () => {
        var registry = new FileDecoration.Registry (ROOT);
        var provider = new FakeProvider (new WorkspaceContext (ROOT));
        registry.add_provider (provider);

        var path = Path.build_filename (ROOT, "a.txt");
        provider.set_decoration (path, new FileDecoration.State (FileDecoration.Tone.WARNING, "Modified"));

        var resolved = registry.decoration_for (path, false);
        assert (resolved != null);
        assert (resolved.tone == FileDecoration.Tone.WARNING);
        assert (resolved.tooltip == "Modified");
    });

    Test.add_func ("/file-decoration-registry/bubbles-to-every-ancestor-up-to-root-and-no-further", () => {
        var registry = new FileDecoration.Registry (ROOT);
        var provider = new FakeProvider (new WorkspaceContext (ROOT));
        registry.add_provider (provider);

        var deep_path = Path.build_filename (ROOT, "a", "b", "c.txt");
        provider.set_decoration (deep_path, new FileDecoration.State (FileDecoration.Tone.WARNING, "Modified"));

        assert (registry.decoration_for (Path.build_filename (ROOT, "a", "b"), true).tone == FileDecoration.Tone.WARNING);
        assert (registry.decoration_for (Path.build_filename (ROOT, "a"), true).tone == FileDecoration.Tone.WARNING);
        assert (registry.decoration_for (ROOT, true).tone == FileDecoration.Tone.WARNING);
        // Nothing above root_path itself gets touched — no entry for it at all.
        assert (registry.decoration_for (Path.get_dirname (ROOT), true) == null);
    });

    Test.add_func ("/file-decoration-registry/folder-with-mixed-descendants-shows-the-worst-tone", () => {
        var registry = new FileDecoration.Registry (ROOT);
        var provider = new FakeProvider (new WorkspaceContext (ROOT));
        registry.add_provider (provider);

        var dir = Path.build_filename (ROOT, "dir");
        provider.set_decoration (Path.build_filename (dir, "new.txt"), new FileDecoration.State (FileDecoration.Tone.SUCCESS, "Untracked"));
        provider.set_decoration (Path.build_filename (dir, "changed.txt"), new FileDecoration.State (FileDecoration.Tone.WARNING, "Modified"));

        assert (registry.decoration_for (dir, true).tone == FileDecoration.Tone.WARNING);
    });

    Test.add_func ("/file-decoration-registry/two-providers-on-one-path-highest-tone-wins-tooltips-join", () => {
        var registry = new FileDecoration.Registry (ROOT);
        var provider_a = new FakeProvider (new WorkspaceContext (ROOT));
        var provider_b = new FakeProvider (new WorkspaceContext (ROOT));
        registry.add_provider (provider_a);
        registry.add_provider (provider_b);

        var path = Path.build_filename (ROOT, "a.txt");
        provider_a.set_decoration (path, new FileDecoration.State (FileDecoration.Tone.WARNING, "Modified"));
        provider_b.set_decoration (path, new FileDecoration.State (FileDecoration.Tone.WARNING, "Linted"));

        var resolved = registry.decoration_for (path, false);
        assert (resolved.tone == FileDecoration.Tone.WARNING);
        assert (resolved.tooltip == "Modified • Linted");

        provider_b.set_decoration (path, new FileDecoration.State (FileDecoration.Tone.ALERT, "Conflicted"));
        resolved = registry.decoration_for (path, false);
        assert (resolved.tone == FileDecoration.Tone.ALERT);
        assert (resolved.tooltip == "Conflicted");
    });

    Test.add_func ("/file-decoration-registry/propagate-false-does-not-bubble", () => {
        var registry = new FileDecoration.Registry (ROOT);
        var provider = new FakeProvider (new WorkspaceContext (ROOT));
        registry.add_provider (provider);

        var dir = Path.build_filename (ROOT, "dir");
        provider.set_decoration (Path.build_filename (dir, "open-tab.txt"), new FileDecoration.State (FileDecoration.Tone.ACCENT, "Open", null, false));

        assert (registry.decoration_for (Path.build_filename (dir, "open-tab.txt"), false).tone == FileDecoration.Tone.ACCENT);
        assert (registry.decoration_for (dir, true) == null);
    });

    Test.add_func ("/file-decoration-registry/a-directorys-own-direct-decoration-beats-an-equal-tone-bubbled-one", () => {
        var registry = new FileDecoration.Registry (ROOT);
        var provider = new FakeProvider (new WorkspaceContext (ROOT));
        registry.add_provider (provider);

        var dir = Path.build_filename (ROOT, "dir");
        provider.set_decoration (Path.build_filename (dir, "child.txt"), new FileDecoration.State (FileDecoration.Tone.WARNING, "Modified"));
        provider.set_decoration (dir, new FileDecoration.State (FileDecoration.Tone.WARNING, "Directly tagged"));

        assert (registry.decoration_for (dir, true).tooltip == "Directly tagged");
    });

    Test.add_func ("/file-decoration-registry/folder-tooltip-is-the-winning-childs-bubble-tooltip", () => {
        var registry = new FileDecoration.Registry (ROOT);
        var provider = new FakeProvider (new WorkspaceContext (ROOT));
        registry.add_provider (provider);

        var dir = Path.build_filename (ROOT, "dir");
        provider.set_decoration (Path.build_filename (dir, "child.txt"), new FileDecoration.State (FileDecoration.Tone.WARNING, "Modified", "Contains modified files"));

        assert (registry.decoration_for (dir, true).bubble_tooltip == "Contains modified files");
    });

    Test.add_func ("/file-decoration-registry/decorations-changed-re-pulls-and-drops-stale-paths", () => {
        var registry = new FileDecoration.Registry (ROOT);
        var provider = new FakeProvider (new WorkspaceContext (ROOT));
        registry.add_provider (provider);

        var path = Path.build_filename (ROOT, "a.txt");
        provider.set_decoration (path, new FileDecoration.State (FileDecoration.Tone.SUCCESS, "Untracked"));
        assert (registry.decoration_for (path, false) != null);

        int changed_count = 0;
        registry.changed.connect (() => changed_count++);
        provider.set_decoration (path, null);

        assert (changed_count == 1);
        assert (registry.decoration_for (path, false) == null);
    });

    Test.add_func ("/file-decoration-registry/remove-provider-clears-everything-it-contributed", () => {
        var registry = new FileDecoration.Registry (ROOT);
        var provider = new FakeProvider (new WorkspaceContext (ROOT));
        registry.add_provider (provider);

        var path = Path.build_filename (ROOT, "a.txt");
        provider.set_decoration (path, new FileDecoration.State (FileDecoration.Tone.WARNING, "Modified"));
        assert (registry.decoration_for (path, false) != null);

        registry.remove_provider (provider);

        assert (registry.decoration_for (path, false) == null);
    });

    Test.add_func ("/file-decoration-registry/add-provider-is-idempotent", () => {
        var registry = new FileDecoration.Registry (ROOT);
        var provider = new FakeProvider (new WorkspaceContext (ROOT));
        registry.add_provider (provider);
        registry.add_provider (provider); // same provider registered twice — must not double up

        var path = Path.build_filename (ROOT, "a.txt");
        provider.set_decoration (path, new FileDecoration.State (FileDecoration.Tone.WARNING, "Modified"));

        // A duplicate registration would double-connect decorations_changed
        // (recompute() running twice per change, harmless on its own) and
        // walk this same provider's own entries twice in recompute(), which
        // merge_direct() would then merge against itself — "Modified"
        // becoming "Modified • Modified" is the observable symptom.
        var resolved = registry.decoration_for (path, false);
        assert (resolved.tooltip == "Modified");
    });

    return Test.run ();
}
