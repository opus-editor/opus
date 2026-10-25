/**
 * Text coming in through the input method rather than as keys: a dead
 * key waiting for its letter (`~` then `a` for `ã`), a compose
 * sequence, a CJK candidate list. GTK composes it in a GtkIMContext
 * and hands the result over in two signals — what is still being
 * composed (preedit) and what was settled on (commit). GtkTextView
 * puts both at the primary cursor alone: the preedit drawn into its
 * layout, the commit inserted into the buffer behind every rule typing
 * has. Here both go to CodeEditorCursors instead — the preedit as
 * marked text at every cursor, the commit typed like any key.
 *
 * The context is the view's own, found through its key controller: it
 * already gets focus from the view, the caret's location for the
 * candidate window, and the text around the caret. The view's handlers
 * for commit and preedit-changed are disconnected (GTK connects them
 * with the view itself as their data, which is how they are told apart
 * from everything else on the context) and replaced by this class's.
 * CodeEditorInput also filters its keys through this same context,
 * ahead of its own dispatch: on a layout where `~` is a dead key, the
 * `a` that follows belongs to the composer, not to type_char().
 */
public class CodeEditorComposition : Object {
  /** The view's own input method context — null only if GTK stopped exposing it, when composing falls back to the view's own behaviour. */
  public Gtk.IMContext? context { get; private set; }

  private CodeEditorCursors cursors;

  public CodeEditorComposition (CodeEditorSourceView text_view, CodeEditorCursors cursors) {
    this.cursors = cursors;
    context = view_context (text_view);
    if (context == null) {
      Logger.warn ("GtkTextView exposes no input method context: composed text will land at the primary cursor only");
      return;
    }
    detach_view_handler (context, text_view, "commit");
    detach_view_handler (context, text_view, "preedit-changed");
    context.commit.connect ((text) => cursors.commit_text (text));
    context.preedit_changed.connect (on_preedit_changed);
    context.preedit_end.connect (() => cursors.clear_preedit ());
  }

  /** Ends a composition in progress — a key the context let through, or a click, means it is over. The context forgets its state; the preedit text goes. */
  public void cancel () {
    if (!cursors.has_preedit) {
      return;
    }
    if (context != null) {
      context.reset ();
    }
    cursors.clear_preedit ();
  }

  private void on_preedit_changed () {
    string text;
    Pango.AttrList attributes;
    int caret;
    context.get_preedit_string (out text, out attributes, out caret);
    cursors.show_preedit (text, caret);
  }

  private static Gtk.IMContext? view_context (Gtk.Widget view) {
    var controllers = view.observe_controllers ();
    for (uint i = 0; i < controllers.get_n_items (); i++) {
      var key_controller = controllers.get_item (i) as Gtk.EventControllerKey;
      if (key_controller != null && key_controller.get_im_context () != null) {
        return key_controller.get_im_context ();
      }
    }
    return null;
  }

  private static void detach_view_handler (Gtk.IMContext context, Gtk.Widget view, string signal_name) {
    uint signal_id = GLib.Signal.lookup (signal_name, typeof (Gtk.IMContext));
    GLib.SignalHandler.disconnect_matched (context, GLib.SignalMatchType.ID | GLib.SignalMatchType.DATA, signal_id, 0, null, null, view);
  }
}
