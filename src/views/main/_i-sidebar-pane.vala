/**
 * A pane Sidebar can mount into its slot for one of the window's own
 * "Editor"/"Git" activities (main-window/index.blp's own `view_stack`)
 * — keeps Sidebar itself generic over which concrete pane fills that
 * slot, the same role IGlobalPanel plays for MainWindow's own
 * bottom-panel slot.
 */
public interface ISidebarPane : Object {
  /** The pane's own real widget — Sidebar mounts this into its slot's Adw.Bin. */
  public abstract Gtk.Widget widget { get; }
}
