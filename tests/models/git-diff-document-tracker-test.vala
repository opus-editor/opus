// GitDiff.DocumentTracker end to end, against a fake IBaseProvider — same
// "fake provider, no real plugin" idiom file-decoration-registry-test.vala
// already uses for FileDecoration.IProvider.

private class FakeProvider : Object, IWorkspaceExtension, GitDiff.IBaseProvider {
    public WorkspaceContext context { get; set; }
    private HashTable<string, GitDiff.Bases> bases = new HashTable<string, GitDiff.Bases> (str_hash, str_equal);
    // Artificial delay before bases_for() resolves — lets a test make one
    // call slower than another, to exercise DocumentTracker's generation
    // guard against a stale set_document() call resolving late.
    private uint delay_ms;

    public FakeProvider (WorkspaceContext context, uint delay_ms = 0) {
        Object (context: context);
        this.delay_ms = delay_ms;
    }

    public void activate () {}
    public void deactivate () {}

    public void set_bases (string path, GitDiff.Bases b) {
        bases[path] = b;
    }

    /** Simulates a commit/stage/checkout happening while a document is active — the real provider fires this from its own `.git` watch, with no action from the host. */
    public void fire_bases_changed (string? path) {
        bases_changed (path);
    }

    public async GitDiff.Bases? bases_for (string path) {
        if (delay_ms > 0) {
            SourceFunc callback = bases_for.callback;
            Timeout.add (delay_ms, () => {
                callback ();
                return Source.REMOVE;
            });
            yield;
        }
        return bases[path];
    }
}

private const string ROOT = "/root";

/** Waits for `tracker`'s own hunks_changed to fire at least once (the debounce + background-thread round trip) — generous timeout so a slow machine doesn't hang this test forever. */
private bool wait_for_hunks_changed (GitDiff.DocumentTracker tracker) {
    var loop = new MainLoop ();
    bool fired = false;
    var handler_id = tracker.hunks_changed.connect (() => {
        fired = true;
        loop.quit ();
    });
    var timeout_id = Timeout.add (2000, () => {
        loop.quit ();
        return Source.REMOVE;
    });
    loop.run ();
    tracker.disconnect (handler_id);
    Source.remove (timeout_id);
    return fired;
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/git-diff-document-tracker/null-path-or-provider-clears-hunks", () => {
        var path = Path.build_filename (ROOT, "a.txt");
        var provider = new FakeProvider (new WorkspaceContext (ROOT));
        provider.set_bases (path, new GitDiff.Bases ("line1\n", null));

        var tracker = new GitDiff.DocumentTracker ();
        tracker.set_document.begin (path, "CHANGED\n", provider);
        assert (wait_for_hunks_changed (tracker));
        assert (tracker.hunks ().length == 1); // a real hunk first, so the next assertion proves this actually cleared it rather than just never having set anything

        tracker.set_document.begin (null, "", null);
        assert (tracker.hunks ().length == 0);
    });

    // Regression: bases_changed used to have no consumer anywhere in the
    // host — a commit/stage/checkout while a document was open never
    // updated its gutter until the next tab switch, because nothing ever
    // re-subscribed to the provider's own signal.
    Test.add_func ("/git-diff-document-tracker/reacts-to-the-providers-own-bases-changed", () => {
        var path = Path.build_filename (ROOT, "a.txt");
        var provider = new FakeProvider (new WorkspaceContext (ROOT));
        provider.set_bases (path, new GitDiff.Bases ("line1\nline2\nline3\n", null));

        var tracker = new GitDiff.DocumentTracker ();
        tracker.set_document.begin (path, "line1\nline2\nline3\n", provider);
        assert (wait_for_hunks_changed (tracker));
        assert (tracker.hunks ().length == 0);

        provider.set_bases (path, new GitDiff.Bases ("line1\nSTAGED\nline3\n", null));
        provider.fire_bases_changed (null);

        assert (wait_for_hunks_changed (tracker));
        var hunks = tracker.hunks ();
        assert (hunks.length == 1);
        assert (hunks[0].kind == GitDiff.HunkKind.CHANGED);
    });

    // bases_changed for an unrelated path shouldn't touch the currently
    // active document at all.
    Test.add_func ("/git-diff-document-tracker/ignores-bases-changed-for-a-different-path", () => {
        var path = Path.build_filename (ROOT, "a.txt");
        var other_path = Path.build_filename (ROOT, "b.txt");
        var provider = new FakeProvider (new WorkspaceContext (ROOT));
        provider.set_bases (path, new GitDiff.Bases ("line1\n", null));

        var tracker = new GitDiff.DocumentTracker ();
        tracker.set_document.begin (path, "line1\n", provider);
        assert (wait_for_hunks_changed (tracker));
        assert (tracker.hunks ().length == 0);

        provider.set_bases (path, new GitDiff.Bases ("CHANGED\n", null));
        provider.fire_bases_changed (other_path);

        // No hunks_changed to wait for here (nothing should have been
        // triggered) — a short, fixed wait instead, then assert the
        // stale bases were never re-fetched.
        var loop = new MainLoop ();
        Timeout.add (400, () => {
            loop.quit ();
            return Source.REMOVE;
        });
        loop.run ();
        assert (tracker.hunks ().length == 0);
    });

    // Regression: set_document() used to always diff against an empty
    // buffer, so a tab switch onto a file that already differed from
    // HEAD showed one giant REMOVED hunk at the top until the user's
    // next keystroke — it must diff against the document's real,
    // already-loaded text from the start.
    Test.add_func ("/git-diff-document-tracker/set-document-diffs-against-the-real-loaded-text", () => {
        var path = Path.build_filename (ROOT, "a.txt");
        var provider = new FakeProvider (new WorkspaceContext (ROOT));
        provider.set_bases (path, new GitDiff.Bases ("line1\nline2\nline3\n", null));

        var tracker = new GitDiff.DocumentTracker ();
        tracker.set_document.begin (path, "line1\nCHANGED\nline3\n", provider);

        assert (wait_for_hunks_changed (tracker));
        var hunks = tracker.hunks ();
        assert (hunks.length == 1);
        assert (hunks[0].kind == GitDiff.HunkKind.CHANGED);
        assert (hunks[0].current_start == 1);
    });

    Test.add_func ("/git-diff-document-tracker/further-edits-are-debounced-and-recomputed", () => {
        var path = Path.build_filename (ROOT, "a.txt");
        var provider = new FakeProvider (new WorkspaceContext (ROOT));
        provider.set_bases (path, new GitDiff.Bases ("line1\nline2\nline3\n", null));

        var tracker = new GitDiff.DocumentTracker ();
        tracker.set_document.begin (path, "line1\nline2\nline3\n", provider);
        assert (wait_for_hunks_changed (tracker));
        assert (tracker.hunks ().length == 0);

        tracker.notify_text_changed ("line1\nCHANGED\nline3\n");
        assert (wait_for_hunks_changed (tracker));
        var hunks = tracker.hunks ();
        assert (hunks.length == 1);
        assert (hunks[0].kind == GitDiff.HunkKind.CHANGED);
        assert (hunks[0].current_start == 1);
    });

    Test.add_func ("/git-diff-document-tracker/a-slower-stale-set-document-never-overwrites-a-newer-one", () => {
        var slow_path = Path.build_filename (ROOT, "slow.txt");
        var slow_provider = new FakeProvider (new WorkspaceContext (ROOT), 300);
        slow_provider.set_bases (slow_path, new GitDiff.Bases ("AAAA\n", null));

        var fast_path = Path.build_filename (ROOT, "fast.txt");
        var fast_provider = new FakeProvider (new WorkspaceContext (ROOT));
        fast_provider.set_bases (fast_path, new GitDiff.Bases ("BBBB\n", null));

        var tracker = new GitDiff.DocumentTracker ();
        tracker.set_document.begin (slow_path, "", slow_provider);
        tracker.set_document.begin (fast_path, "", fast_provider);

        // Unconditional wait, long enough for both the fast call's own
        // round trip and the slow call's artificial 300ms delay to have
        // had every chance to land — the generation guard should have
        // discarded the slow (stale) one by now.
        var settle_loop = new MainLoop ();
        Timeout.add (600, () => {
            settle_loop.quit ();
            return Source.REMOVE;
        });
        settle_loop.run ();

        // Matches fast's own base exactly: if the stale slow call had
        // incorrectly won, this diff would show one CHANGED hunk (AAAA
        // vs BBBB) instead of none.
        tracker.notify_text_changed ("BBBB\n");
        assert (wait_for_hunks_changed (tracker));
        assert (tracker.hunks ().length == 0);
    });

    return Test.run ();
}
