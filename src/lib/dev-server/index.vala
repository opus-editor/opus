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
   * (`io.github.opus_editor.Opus`, already owned by Adw.Application/GApplication
   * itself) rather than owning a second name of its own — this interface is
   * exported as one more object alongside GApplication's own, at
   * `<app's own object path>/Dev`.
   *
   * Deliberately thin: every method here just calls straight through to an
   * EditorView.EditorPaneWidget's own already-public surface. The Document-
   * only entry points (active_content, set_active_content(), the cursor
   * pair, save_path()) exist only because this needed to reach them from
   * outside, not because the real UI needed them — so they live on
   * EditorView.EditorPane.TabDocument, reached through the pane's own
   * public `document_tab` rather than wrapped in one forwarding method
   * each; key_press()/select_all() and the search_* methods reach the
   * real CodeEditor the same way (`code_editor`/`search_editor`). Nothing
   * here holds business logic of its own, and nothing outside this file/
   * DEBUG-gated call site knows this class exists — deleting it wouldn't
   * change anything else in the app.
   *
   * Implements IDevServer (see its own doc comment, _i-dev-server.vala,
   * for why that's a separate type) rather than declaring the D-Bus contract
   * directly on this class — this class is free to have other public
   * methods (add_session(), remove_session(), start()) that take plain GTK
   * objects, without those leaking into the D-Bus surface.
   */
  public class DevServer : Object, IDevServer {
    // One entry per open MainWindow — App adds/removes as windows
    // open/close (see App.create_window()'s own #if DEBUG block). Every
    // method here operates on whichever one was added *last*: good
    // enough for a one-window dev loop, which is the only scenario this
    // was actually built for — resolving "which window" properly would
    // need a whole addressing scheme for a case that doesn't come up in
    // practice. The window, not just its EditorPaneWidget: the Command
    // Bar methods below need the window itself.
    private GenericArray<MainWindow> windows = new GenericArray<MainWindow> ();
    private uint registration_id = 0;

    // search_position_changed is an event, not a queryable property —
    // search_get_position() (the only reader) needs the *last* reported
    // (position, count) to still be around after the signal itself has
    // already fired and returned. Lives here, not on EditorPaneWidget: this
    // bookkeeping exists purely so a system test (with no real FindBar
    // to read a counter label off of) can ask "what did it last say",
    // same reasoning as every other field on this class — EditorPaneWidget
    // itself has no use for its own past search results.
    private int last_search_position = 0;
    private int last_search_count = 0;

    public void add_session (MainWindow window) {
      windows.add (window);
      window.editor_pane.search_position_changed.connect ((position, count) => {
        last_search_position = position;
        last_search_count = count;
      });
    }

    public void remove_session (MainWindow window) {
      uint index;
      if (windows.find (window, out index)) {
        windows.remove_index (index);
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

    private MainWindow current_window () throws DBusError {
      if (windows.length == 0) {
        throw new DBusError.FAILED ("No Opus window is open");
      }
      return windows[windows.length - 1];
    }

    private EditorView.EditorPaneWidget current_editor_pane () throws DBusError {
      return current_window ().editor_pane;
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
      current_editor_pane ().document_tab.save_path.begin (path);
    }

    public void set_active_text (string text) throws DBusError, IOError {
      current_editor_pane ().document_tab.set_active_content (text);
    }

    public void set_active_cursors (int[] anchors, int[] positions) throws DBusError, IOError {
      current_editor_pane ().document_tab.set_active_cursors (anchors, positions);
    }

    public string syntax_style_at (int offset) throws DBusError, IOError {
      return current_editor_pane ().code_editor.syntax_style_at (offset);
    }

    public string get_active_text () throws DBusError, IOError {
      return current_editor_pane ().document_tab.active_content;
    }

    public void get_active_cursors (out int[] anchors, out int[] positions) throws DBusError, IOError {
      current_editor_pane ().document_tab.get_active_cursors (out anchors, out positions);
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

    /** The active tab's own text search — throws rather than silently doing nothing on a tab that has none (Find Results), so a test driving search there by mistake fails loudly, same as every other method here with no window to act on. */
    private CodeEditor search_editor () throws DBusError {
      var editor = current_editor_pane ().search_editor;
      if (editor == null) {
        throw new DBusError.FAILED ("The active tab has no text search");
      }
      return editor;
    }

    public void search_set_text (string text) throws DBusError, IOError {
      search_editor ().set_search_text (text);
    }

    public void search_set_options (bool regex, bool case_sensitive, bool whole_word) throws DBusError, IOError {
      search_editor ().set_search_options (regex, case_sensitive, whole_word);
    }

    public void search_next () throws DBusError, IOError {
      search_editor ().search_next ();
    }

    public void search_previous () throws DBusError, IOError {
      search_editor ().search_previous ();
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

    public void reopen_closed_tab () throws DBusError, IOError {
      current_window ().reopen_closed_tab ();
    }

    public void open_command_bar () throws DBusError, IOError {
      current_window ().open_command_bar ();
    }

    public void open_commands () throws DBusError, IOError {
      current_window ().open_commands ();
    }

    public void command_bar_set_text (string text) throws DBusError, IOError {
      current_window ().command_bar_set_text (text);
    }

    public void command_bar_accept () throws DBusError, IOError {
      current_window ().command_bar_accept ();
    }

    public void command_bar_close () throws DBusError, IOError {
      current_window ().close_command_bar ();
    }

    public string command_bar_empty_message () throws DBusError, IOError {
      return current_window ().command_bar_empty_message ();
    }

    public int get_previewed_line () throws DBusError, IOError {
      return current_editor_pane ().code_editor.previewed_line;
    }

    public string[] command_bar_list_items () throws DBusError, IOError {
      return current_window ().command_bar_item_ids ();
    }
  }
}
