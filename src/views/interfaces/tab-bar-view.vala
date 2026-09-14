/** What the user chose when asked about a tab with unsaved changes. */
public enum DiscardChoice {
    SAVE,
    DISCARD,
    CANCEL,
}

/**
 * Facade for the row of open-file tabs above the editor pane. A Controller
 * only ever sees this interface — never the Gtk widgets backing it.
 */
public interface ITabBarView : Object {
    /** A tab was clicked (single-click — makes it active). */
    public signal void tab_selected (string path);

    /** A tab's close control was clicked. */
    public signal void tab_close_requested (string path);

    /** A tab was double-clicked (promotes a preview tab to permanent). */
    public signal void tab_double_clicked (string path);

    /** Adds a tab for `path`, titled `label`; `preview` renders it italic. */
    public abstract void add_tab (string path, string label, bool preview);

    /** Removes the tab for `path`, if present. */
    public abstract void remove_tab (string path);

    /** Marks the tab for `path` as the active one. */
    public abstract void set_active (string path);

    /** Toggles the preview (italic) styling for the tab at `path`. */
    public abstract void mark_preview (string path, bool preview);

    /** Toggles the unsaved-changes indicator for the tab at `path`. */
    public abstract void mark_modified (string path, bool modified);

    /**
     * Asks the user what to do about unsaved changes in `filename` before
     * closing its tab. The real Gtk view backs this with an
     * Adw.AlertDialog; a test fake returns a canned choice.
     */
    public abstract async DiscardChoice confirm_unsaved_close (string filename);
}
