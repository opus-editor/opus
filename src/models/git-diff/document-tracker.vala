/**
 * Per-TabDocument, not per-document: EditorView.EditorPane.TabDocument owns exactly one shared
 * GtkSource.Buffer, fully reloaded on every tab switch — only the
 * currently active document's hunks are ever rendered, so there's no
 * per-document cache/map here, just whichever document is "current" now.
 */
namespace GitDiff {
  public class DocumentTracker : Object {
    private const uint DEBOUNCE_MS = 250; // VS Code's own cited number

    private string? head_tmp_path = null;
    private string? index_tmp_path = null;
    private string? tmp_dir = null;
    private string current_text = "";
    private string? current_path = null;
    private IBaseProvider? current_provider = null;
    private ulong provider_signal_handler = 0;
    // True from the moment set_document() starts awaiting bases_for()
    // until it either bails out (superseded) or hands off to
    // recompute() — guards notify_text_changed()'s own debounced
    // recompute from running against temp files that were just cleared
    // and haven't been rewritten yet (see notify_text_changed's own
    // comment).
    private bool loading = false;
    // Same idiom as EditorView.EditorPane.TabFindResults.search_generation: bumped before every
    // await, checked after resume, so a slower stale call never
    // overwrites a newer one's result.
    private int generation = 0;
    private uint pending_debounce_id = 0;
    private Hunk[] _hunks = {};

    ~DocumentTracker () {
      disconnect_provider ();
      cancel_pending_debounce ();
      clear_temp_files ();
    }

    /** A method, not a property: GObject's property system has no GParamSpec for "array of a custom Object subtype" — same reason GitStatus.paths() is a method too. */
    public Hunk[] hunks () {
      return _hunks;
    }

    public signal void hunks_changed ();

    /**
     * Tab switch: re-fetches both bases from `provider`, rewrites the
     * two temp files, recomputes against `text` — the document's real,
     * already-loaded content, not an empty buffer. Diffing against ""
     * here (as an earlier version of this method did) made every hunk
     * read as one giant REMOVED marker at the top of the file until the
     * user's next keystroke ever called notify_text_changed(), since
     * that's the only other place current_text gets updated.
     *
     * `path` null (untitled/internal tab) or `provider` null (no folder
     * linked / no plugin) both clear hunks immediately, no subprocess
     * call.
     */
    public async void set_document (string? path, string text, IBaseProvider? provider) {
      clear_temp_files ();
      cancel_pending_debounce ();
      int my_generation = ++generation;
      current_text = text;
      current_path = path;

      // Only touch the subscription when the provider itself actually
      // changes — re-subscribing to the exact same provider/method pair
      // on every re-fetch (e.g. one triggered by that same provider's
      // own bases_changed) is pure churn, and empirically not safe: it
      // reconnects the identical bound-method closure over `this` right
      // after disconnecting it, which reproducibly finalized this very
      // object mid-call in testing (signal connections don't keep an
      // object alive — see docs/DECISIONS.md).
      if (provider != current_provider) {
        disconnect_provider ();
        current_provider = provider;
        if (provider != null) {
          connect_provider (provider);
        }
      }

      if (path == null || provider == null) {
        set_hunks ({});
        return;
      }

      loading = true;
      var bases = yield provider.bases_for (path);
      loading = false;
      if (my_generation != generation) {
        return; // a newer set_document/tab-switch superseded this one
      }

      write_temp_files (bases);
      recompute (my_generation);
    }

    /** Called on every keystroke — debounced, no base re-fetch, cheap. */
    public void notify_text_changed (string new_text) {
      current_text = new_text;
      cancel_pending_debounce ();

      int my_generation = generation;
      pending_debounce_id = Timeout.add (DEBOUNCE_MS, () => {
        pending_debounce_id = 0;
        // A set_document() call that's still awaiting bases_for() has
        // already cleared the temp files and hasn't rewritten them yet
        // — recomputing now would diff against no base at all. Skipping
        // is safe: set_document()'s own recompute(), once it resumes,
        // reads current_text fresh (already updated above), so this
        // edit isn't lost, just picked up by that call instead.
        if (!loading) {
          recompute (my_generation);
        }
        return Source.REMOVE;
      });
    }

    /**
     * `path` null means "everything, re-check whatever's currently
     * tracked" — otherwise a change to some other file doesn't affect
     * what's currently displayed.
     *
     * Deferred via Idle.add, not called directly: reacting synchronously
     * from within `provider`'s own signal emission risks GObject
     * invoking a handler connected during that same emission again
     * within the SAME round (documented GLib behavior — "if handlers
     * are added during emission ... they may ... be called").
     *
     * `self` is a real local, not just `this` used implicitly inside
     * the closure below: a GSource closure's implicit capture of `this`
     * for a plain method call doesn't reliably take its own strong
     * reference the way capturing an explicit local variable does —
     * confirmed live, the bare-`this` version let this whole object get
     * finalized mid-flight (its own destructor firing before the
     * deferred call it had just started even finished), reproducibly
     * crashing with `GLib-GObject-FATAL-CRITICAL: ... has no handler
     * with id ...` on the now-dangling signal connection.
     */
    private void on_bases_changed (string? path) {
      if (current_path == null || current_provider == null) {
        return;
      }
      if (path != null && path != current_path) {
        return;
      }
      DocumentTracker self = this;
      Idle.add (() => {
        self.set_document.begin (self.current_path, self.current_text, self.current_provider);
        return Source.REMOVE;
      });
    }

    private void connect_provider (IBaseProvider provider) {
      provider_signal_handler = provider.bases_changed.connect (on_bases_changed);
    }

    /**
     * `g_signal_handler_is_connected` isn't in the GLib vapi, so it's
     * declared here directly — needed because a signal connected to a
     * bound instance method (this class's own `on_bases_changed`) is
     * automatically disconnected by GObject the moment the connected
     * object itself is destroyed, with no notification back to this
     * class's own `provider_signal_handler` field. Without this check,
     * a later explicit disconnect_provider() call using that now-stale
     * id aborts the process outright
     * (`GLib-GObject-FATAL-CRITICAL: ... has no handler with id ...`),
     * confirmed live in testing.
     */
    [CCode (cname = "g_signal_handler_is_connected")]
    private extern static bool signal_handler_is_connected (void* instance, ulong handler_id);

    private void disconnect_provider () {
      if (current_provider != null && provider_signal_handler != 0
          && signal_handler_is_connected (current_provider, provider_signal_handler)) {
        current_provider.disconnect (provider_signal_handler);
      }
      provider_signal_handler = 0;
    }

    private void cancel_pending_debounce () {
      if (pending_debounce_id != 0) {
        Source.remove (pending_debounce_id);
        pending_debounce_id = 0;
      }
    }

    /** Runs the subprocess pair off the main thread — a debounce tick only fires once per typing pause, but a large file's git-diff subprocess could still stall the UI for a perceptible moment otherwise. */
    private void recompute (int my_generation) {
      var head = head_tmp_path;
      var index = index_tmp_path;
      var text = current_text;

      new Thread<void> ("git-diff", () => {
        var new_hunks = Engine.compute_hunks (head, index, text);
        Idle.add (() => {
          if (my_generation == generation) {
            set_hunks (new_hunks);
          }
          return Source.REMOVE;
        });
      });
    }

    private void set_hunks (Hunk[] new_hunks) {
      _hunks = new_hunks;
      hunks_changed ();
    }

    /**
     * Written once per set_document() call, read many times across
     * notify_text_changed()'s debounced recomputes — not per-keystroke.
     * Under HostCommand.shared_tmp_dir(), not the plain tmp dir: these
     * files are read by `git diff`, which inside a Flatpak may run on
     * the host, where the sandbox's own /tmp is invisible.
     */
    private void write_temp_files (Bases? bases) {
      if (bases == null || (bases.head_text == null && bases.index_text == null)) {
        return;
      }

      try {
        tmp_dir = DirUtils.mkdtemp (Path.build_filename (HostCommand.shared_tmp_dir ("git"), "opus-diff-base-XXXXXX"));
        if (bases.head_text != null) {
          head_tmp_path = Path.build_filename (tmp_dir, "head");
          FileUtils.set_contents (head_tmp_path, bases.head_text);
        }
        if (bases.index_text != null) {
          index_tmp_path = Path.build_filename (tmp_dir, "index");
          FileUtils.set_contents (index_tmp_path, bases.index_text);
        }
      } catch (Error e) {
        // clear_temp_files(), not just nulling the path fields: if the
        // index write failed after the head write already succeeded,
        // leaving that real file behind while forgetting its own path
        // would make a later clear_temp_files() call skip removing it,
        // and then fail to remove tmp_dir itself (non-empty) — a real,
        // confirmed leak (24 leftover /tmp/opus-diff-base-* directories
        // from one session).
        clear_temp_files ();
      }
    }

    private void clear_temp_files () {
      if (tmp_dir == null) {
        return;
      }
      if (head_tmp_path != null) {
        FileUtils.remove (head_tmp_path);
      }
      if (index_tmp_path != null) {
        FileUtils.remove (index_tmp_path);
      }
      DirUtils.remove (tmp_dir);
      tmp_dir = null;
      head_tmp_path = null;
      index_tmp_path = null;
    }
  }
}
