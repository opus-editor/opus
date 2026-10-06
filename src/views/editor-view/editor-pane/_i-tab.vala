namespace EditorView.EditorPane {
  /**
   * What the active tab can do, for the shortcuts and menu items whose
   * fallback is a window-level panel rather than a plain no-op — only
   * MainWindow can open FindBar, so it has to be able to ask instead of
   * assuming every tab is a text editor.
   */
  [Flags]
  public enum TabCapability {
    /** FindBar applies: Ctrl+F, the Find menu's Find…/Replace… items, and Ctrl+H falling back to FindBar's replace mode. `search_editor` is non-null. */
    TEXT_SEARCH,
    /** Ctrl+H is handled inside the tab itself (open_replace()). */
    INLINE_REPLACE,
  }

  /**
   * One object per pane per *kind* of tab (a document, Find Results, …),
   * owning every tab of that kind and rendering whichever one is active.
   * EditorPaneWidget routes TabBar gestures and window shortcuts here and
   * turns the chrome signals below into TabBar calls — a kind never
   * touches TabBar itself (a sibling it doesn't own).
   *
   * The shortcut methods have no-op defaults on purpose: a kind
   * overrides only what a shortcut means for it, so adding a shortcut
   * doesn't force an empty override into every kind that ignores it.
   */
  public interface ITabKind : Object {
    /** Shown in the pane's editor area while a tab of this kind is active. */
    public abstract Gtk.Widget widget { get; }
    public abstract TabCapability capabilities { get; }
    /** The editor FindBar acts on — non-null exactly when capabilities has TEXT_SEARCH. */
    public virtual CodeEditor? search_editor { get { return null; } }

    public abstract bool owns (string uri);
    public abstract bool is_dirty (string uri);
    /** `uri` just became the active tab — render it. */
    public abstract void show (string uri);
    /** No tab of this kind is active any more (another kind's tab is, or none) — release whatever show() bound. */
    public abstract void hide ();
    /** Same unsaved-changes flow as the tab's own close button; may end up not closing. Emits tab_removed when it does. */
    public abstract async void close_tab (string uri);
    /** Closes `uri` outright, no prompt — the default is close_tab() itself, right for a kind with nothing to ever prompt about. */
    public virtual void discard_tab (string uri) {
      close_tab.begin (uri);
    }
    /** Window teardown. */
    public abstract void close ();

    public virtual void zoom_in () { }
    public virtual void zoom_out () { }
    public virtual void reset_zoom () { }
    /** Only reached when capabilities has INLINE_REPLACE. */
    public virtual void open_replace () { }
    /** Make `uri` permanent if it was a preview — a no-op for kinds without previews. */
    public virtual void promote (string uri) { }

    // Chrome, for the pane to forward to TabBar (mirrors TabBar.add_tab/
    // remove_tab/rename_tab/mark_*). `title` is the clean, user-facing
    // identity (a real path, or a display name) — see TabBar.add_tab()'s
    // own `tooltip_path` doc comment. `has_pathname` is whether the tab
    // is backed by a real on-disk path right now — false for Untitled-N
    // and Find Results — and can flip to true in tab_renamed (Save As on
    // an untitled tab).
    public signal void tab_added (string uri, string name, string folder_name, bool preview, string title, bool has_pathname);
    public signal void tab_removed (string uri);
    public signal void tab_renamed (string old_uri, string new_uri, string name, string folder_name, string title, bool has_pathname);
    public signal void tab_marks_changed (string uri, bool modified, bool deleted, bool unsynchronized);
    public signal void tab_preview_changed (string uri, bool preview);
    public signal void tab_decoration_changed (string uri, FileDecoration.State? decoration);
    public signal void activate_requested (string uri);
    /** Re-emitted from search_editor; the pane re-emits it onward only while this kind is active. */
    public signal void search_position_changed (int position, int count);
  }
}
