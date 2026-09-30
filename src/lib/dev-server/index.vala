namespace Opus.Dev {
  /**
   * A D-Bus control surface for whichever Opus windows are currently open —
   * exists purely so the assistant working on this codebase can drive the
   * real, already-running app from the terminal (`gdbus call …`) instead of
   * reconstructing a throwaway harness for every check. Debug builds only
   * (see main.vala's own `#if DEBUG` around where this gets constructed and
   * started) — never registered, so never reachable, in a release build.
   *
   * Piggybacks on the application's own existing D-Bus connection/bus name
   * (`io.github.nowaos.Opus`, already owned by Adw.Application/GApplication
   * itself) rather than owning a second name of its own — this interface is
   * exported as one more object alongside GApplication's own, at
   * `<app's own object path>/Dev`.
   *
   * Deliberately thin: every method here just calls straight through to an
   * EditorView.EditorPane's own already-public methods (a couple of which —
   * open_paths(), active_content, set_active_content(), and making
   * save_path() itself public — exist only because this needed to reach
   * them from outside, not because the real UI needed them; see EditorPane's
   * own class doc comment). key_press()/select_all() reach one level deeper,
   * into the real EditorPane.code_editor itself (exposed directly for
   * exactly this — see its own doc comment for why there's no forwarding
   * method for either on EditorPane). Nothing here holds business logic of
   * its own, and nothing outside this file/DEBUG-gated call site knows this
   * class exists — deleting it wouldn't change anything else in the app.
   *
   * Implements IDevServer (see its own doc comment, _i-dev-server.vala,
   * for why that's a separate type) rather than declaring the D-Bus contract
   * directly on this class — this class is free to have other public
   * methods (add_session(), remove_session(), start()) that take plain GTK
   * objects, without those leaking into the D-Bus surface.
   */
  public class DevServer : Object, IDevServer {
    // One entry per open window's own EditorView.EditorPane — main.vala
    // adds/removes as windows open/close (see build_session()'s own
    // #if DEBUG block). Every method here operates on whichever one
    // was added *last*: good enough for a one-window dev loop, which
    // is the only scenario this was actually built for — resolving
    // "which window" properly would need a whole addressing scheme
    // for a case that doesn't come up in practice.
    private GenericArray<EditorView.EditorPane> editor_panes = new GenericArray<EditorView.EditorPane> ();
    private uint registration_id = 0;

    // search_position_changed is an event, not a queryable property —
    // search_get_position() (the only reader) needs the *last* reported
    // (position, count) to still be around after the signal itself has
    // already fired and returned. Lives here, not on EditorPane: this
    // bookkeeping exists purely so a system test (with no real FindBar
    // to read a counter label off of) can ask "what did it last say",
    // same reasoning as every other field on this class — EditorPane
    // itself has no use for its own past search results.
    private int last_search_position = 0;
    private int last_search_count = 0;

    public void add_session (EditorView.EditorPane editor_pane) {
      editor_panes.add (editor_pane);
      editor_pane.search_position_changed.connect ((position, count) => {
        last_search_position = position;
        last_search_count = count;
      });
    }

    public void remove_session (EditorView.EditorPane editor_pane) {
      uint index;
      if (editor_panes.find (editor_pane, out index)) {
        editor_panes.remove_index (index);
      }
    }

    /** Exports this interface on `connection` at `object_path` — called once the application's own D-Bus connection actually exists (main.vala's own Adw.Application.startup handler), not before. */
    public void start (DBusConnection connection, string object_path) {
      if (registration_id != 0) {
        return;
      }

      try {
        registration_id = connection.register_object (object_path, (IDevServer) this);
      } catch (IOError e) {
        warning ("failed to start the dev D-Bus server: %s", e.message);
      }
    }

    private EditorView.EditorPane current_editor_pane () throws DBusError {
      if (editor_panes.length == 0) {
        throw new DBusError.FAILED ("No Opus window is open");
      }
      return editor_panes[editor_panes.length - 1];
    }

    public void new_file () throws DBusError, IOError {
      current_editor_pane ().new_untitled ();
    }

    public void open_tab (string path) throws DBusError, IOError {
      try {
        current_editor_pane ().open (path, true);
      } catch (Error e) {
        throw new IOError.FAILED (e.message);
      }
    }

    public void close_tab (string path) throws DBusError, IOError {
      current_editor_pane ().discard_tab (path);
    }

    public void save_tab (string path) throws DBusError, IOError {
      current_editor_pane ().save_path.begin (path);
    }

    public void set_active_text (string text) throws DBusError, IOError {
      current_editor_pane ().set_active_content (text);
    }

    public void set_active_cursors (int[] anchors, int[] positions) throws DBusError, IOError {
      current_editor_pane ().set_active_cursors (anchors, positions);
    }

    public string get_active_text () throws DBusError, IOError {
      return current_editor_pane ().active_content;
    }

    public void get_active_cursors (out int[] anchors, out int[] positions) throws DBusError, IOError {
      current_editor_pane ().get_active_cursors (out anchors, out positions);
    }

    public bool key_press (uint keyval, uint modifiers) throws DBusError, IOError {
      return current_editor_pane ().code_editor.key_pressed (keyval, modifiers);
    }

    public void select_all () throws DBusError, IOError {
      current_editor_pane ().code_editor.select_all ();
    }

    public string[] list_open_tabs () throws DBusError, IOError {
      return current_editor_pane ().open_paths ();
    }

    public string get_active_tab () throws DBusError, IOError {
      return current_editor_pane ().active_document_path ?? "";
    }

    public bool is_dirty (string path) throws DBusError, IOError {
      return current_editor_pane ().is_dirty (path);
    }

    public void search_set_text (string text) throws DBusError, IOError {
      current_editor_pane ().set_search_text (text);
    }

    public void search_set_options (bool regex, bool case_sensitive, bool whole_word) throws DBusError, IOError {
      current_editor_pane ().set_search_options (regex, case_sensitive, whole_word);
    }

    public void search_next () throws DBusError, IOError {
      current_editor_pane ().search_next ();
    }

    public void search_previous () throws DBusError, IOError {
      current_editor_pane ().search_previous ();
    }

    public void search_get_position (out int position, out int count) throws DBusError, IOError {
      current_editor_pane (); // Throws if no window is open — same guard every other method here gets, even though the actual read is off this class's own fields.
      position = last_search_position;
      count = last_search_count;
    }

    public void find_in_files (string text) throws DBusError, IOError {
      var query = new FindInFilesQuery () { text = text };
      current_editor_pane ().search_in_files.begin (query);
    }
  }
}
