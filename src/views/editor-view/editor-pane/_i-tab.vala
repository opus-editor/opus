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
   * One open tab: its own widget, kept alive and laid out for as long
   * as the tab exists, so coming back to it shows it exactly as it was
   * left — the GNOME Text Editor shape (an EditorPage per tab).
   * EditorPaneWidget keeps the registry, shows the active one, routes
   * TabBar gestures and window shortcuts here, and turns the chrome
   * signals below into TabBar calls — a tab never touches TabBar
   * itself (a sibling it doesn't own).
   *
   * The shortcut methods have no-op defaults on purpose: a tab
   * overrides only what a shortcut means for it.
   */
  public interface ITab : Object {
    /** The registry key — a file's `file://` uri, `untitled://N`, or a synthetic one. */
    public abstract string uri { owned get; }
    /** The clean, user-facing identity: a real path, or a display name ("Untitled-1", "Find Results") — what DevServer and Copy Path get. */
    public abstract string title { owned get; }
    /** The tab's label. */
    public abstract string name { owned get; }
    /** The label's folder suffix, "" for none. */
    public abstract string folder_name { owned get; }
    /** Whether a real on-disk path backs the tab right now — can flip to true on Save As. */
    public abstract bool has_pathname { get; }
    public abstract bool is_preview { get; }
    public abstract bool is_dirty { get; }

    /** Shown in the pane's editor area while this tab is active. */
    public abstract Gtk.Widget widget { get; }
    public abstract TabCapability capabilities { get; }
    /** The editor FindBar acts on — non-null exactly when capabilities has TEXT_SEARCH. */
    public virtual CodeEditor? search_editor { get { return null; } }

    /** This tab just became the active one. */
    public abstract void shown ();
    /** Another tab (or none) is active now. */
    public abstract void hidden ();
    /** Same unsaved-changes flow as the tab's own close button; may end up not closing. Emits `closed` when it does. */
    public abstract async void close ();
    /** Closes outright, no prompt — the default is close() itself, right for a tab with nothing to ever prompt about. */
    public virtual void discard () {
      close.begin ();
    }
    /** Takes the tab apart once it has left the pane (or the window is going): whatever it listens to or watches, undone. */
    public abstract void dispose_tab ();

    public virtual void zoom_in () { }
    public virtual void zoom_out () { }
    public virtual void reset_zoom () { }
    /** Only reached when capabilities has INLINE_REPLACE. */
    public virtual void open_replace () { }
    /** Make the tab permanent if it was a preview — a no-op for tabs without previews. */
    public virtual void promote () { }

    // Chrome, for the pane to forward to TabBar (mirrors TabBar's
    // remove_tab/rename_tab/mark_*).
    /** The tab left: closed, discarded, or evicted as an old preview. */
    public signal void closed ();
    /** `uri`/`title`/`name` changed (Save As, the file moved) — `old_uri` is the key the pane knew it by. */
    public signal void renamed (string old_uri);
    public signal void marks_changed (bool modified, bool deleted, bool unsynchronized);
    public signal void preview_changed (bool preview);
    public signal void decoration_changed (FileDecoration.State? decoration);
    public signal void activate_requested ();
    /** Re-emitted from search_editor; the pane re-emits it onward only while this tab is active. */
    public signal void search_position_changed (int position, int count);
  }
}
