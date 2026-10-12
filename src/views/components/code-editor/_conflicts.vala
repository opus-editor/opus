/**
 * Merge-conflict blocks in an editable buffer: each `<<<<<<<` … `>>>>>>>`
 * block found by GitDiff.ConflictParser gets its current, base and
 * incoming lines tinted edge to edge (CodeEditorSourceView's row bands —
 * a tag's paragraph background would skip empty lines), the `<<<<<<<`
 * and `>>>>>>>` lines in their block's own tone a shade stronger,
 * `=======` plain. The
 * actions — "Use HEAD", "Use <branch>", "Use both", named after the
 * block's own markers — live on one floating
 * toolbar at the bottom of the editor (a Gtk.Overlay child, so it sits
 * in widget coordinates and never has to chase the text), shown while
 * the cursor is inside a block and acting on that block. Accepting
 * replaces the whole block, markers included, through CodeEditor's own
 * external-edit path, so it is one undoable step. Every text change
 * re-parses at once (one pass over the lines); a read-only editor (a
 * diff) never shows any of this.
 */
public class CodeEditorConflicts : Object {
  private unowned CodeEditor editor;
  private CodeEditorSourceView text_view;
  private Gtk.TextBuffer buffer { get { return text_view.buffer; } }
  private GenericArray<GitDiff.Conflict> conflicts = new GenericArray<GitDiff.Conflict> ();
  private Gtk.Box[] swatches = {};
  private Gtk.Box toolbar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
  private Gtk.Button current_button;
  private Gtk.Button incoming_button;
  private ulong cursor_handler = 0;
  // The block the cursor is in, -1 for none — what the toolbar acts on.
  private int active = -1;

  /** The floating toolbar — CodeEditor puts it over the editor. Hidden until the cursor enters a block. */
  public Gtk.Widget widget { get { return toolbar; } }

  public CodeEditorConflicts (CodeEditor editor, CodeEditorSourceView text_view) {
    this.editor = editor;
    this.text_view = text_view;
    foreach (var tone in new string[] { "conflict-current-marker", "conflict-incoming-marker", "conflict-current-line", "conflict-base-line", "conflict-incoming-line" }) {
      var swatch = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) { can_target = false };
      swatch.add_css_class (tone);
      text_view.add_overlay (swatch, 0, 0);
      swatches += swatch;
    }
    toolbar.add_css_class ("conflict-toolbar");
    toolbar.halign = Gtk.Align.CENTER;
    toolbar.valign = Gtk.Align.END;
    toolbar.margin_bottom = 16;
    toolbar.visible = false;
    current_button = action (_("Use current"), "current");
    incoming_button = action (_("Use incoming"), "incoming");
    toolbar.append (current_button);
    toolbar.append (new Gtk.Separator (Gtk.Orientation.VERTICAL) { margin_top = 4, margin_bottom = 4 });
    toolbar.append (incoming_button);
    toolbar.append (new Gtk.Separator (Gtk.Orientation.VERTICAL) { margin_top = 4, margin_bottom = 4 });
    toolbar.append (action (_("Use both"), "both"));
    cursor_handler = buffer.notify["cursor-position"].connect (() => update_active ());
  }

  public int count { get { return (int) conflicts.length; } }

  /** The text changed (or was loaded): parsed again right away. */
  public void schedule_scan () {
    scan ();
  }

  public void close () {
    buffer.disconnect (cursor_handler);
  }

  /** The theme changed: the tints are read again from CSS and the bands repainted. */
  public void reload_colors () {
    paint ();
  }

  /**
   * Resolves conflict number `index` (top to bottom) with `side`:
   * "current", "incoming", "both" (current then incoming) or
   * "both-incoming-first".
   */
  public void accept (int index, string side) throws Error {
    if (index < 0 || index >= conflicts.length) {
      throw new IOError.NOT_FOUND ("No conflict #%d".printf (index));
    }
    var conflict = conflicts[index];
    var current = lines_text (conflict.current_first, conflict.current_last);
    var incoming = lines_text (conflict.incoming_first, conflict.incoming_last);
    string replacement;
    switch (side) {
      case "current": replacement = current; break;
      case "incoming": replacement = incoming; break;
      case "both": replacement = current + incoming; break;
      case "both-incoming-first": replacement = incoming + current; break;
      default: throw new IOError.INVALID_ARGUMENT ("Unknown side “%s”".printf (side));
    }
    Gtk.TextIter start, end;
    buffer.get_iter_at_line (out start, conflict.start_line);
    if (!buffer.get_iter_at_line (out end, conflict.end_line + 1)) {
      buffer.get_end_iter (out end);
    }
    var edit = new TextEdit () {
      start_offset = start.get_offset (),
      end_offset = end.get_offset (),
      old_text = buffer.get_text (start, end, true),
      new_text = replacement,
    };
    editor.apply_external_edits ({ edit });
  }

  /** Lines `first`..`last` inclusive, each with its newline — "" for an empty range. */
  private string lines_text (int first, int last) {
    if (last < first) {
      return "";
    }
    Gtk.TextIter start, end;
    buffer.get_iter_at_line (out start, first);
    if (!buffer.get_iter_at_line (out end, last + 1)) {
      buffer.get_end_iter (out end);
      var text = buffer.get_text (start, end, true);
      return text.has_suffix ("\n") ? text : text + "\n";
    }
    return buffer.get_text (start, end, true);
  }

  private void scan () {
    var text = buffer.text;
    if (editor.read_only || !text.contains ("<<<<<<< ")) {
      conflicts = new GenericArray<GitDiff.Conflict> ();
    } else {
      conflicts = GitDiff.ConflictParser.parse (text);
    }
    paint ();
    update_active ();
  }

  private void paint () {
    var bands = new GenericArray<CodeEditorSourceView.RowBand> ();
    for (uint i = 0; i < conflicts.length; i++) {
      var c = conflicts[i];
      band (bands, c.start_line, c.start_line, swatches[0]);
      band (bands, c.current_first, c.current_last, swatches[2]);
      if (c.base_line >= 0) {
        band (bands, c.base_line, c.splitter_line - 1, swatches[3]);
      }
      band (bands, c.incoming_first, c.incoming_last, swatches[4]);
      band (bands, c.end_line, c.end_line, swatches[1]);
    }
    text_view.set_row_bands ("conflicts", bands);
  }

  private static void band (GenericArray<CodeEditorSourceView.RowBand> bands, int first, int last, Gtk.Widget swatch) {
    if (last >= first) {
      bands.add (new CodeEditorSourceView.RowBand (first, last, swatch));
    }
  }

  /** Which block the cursor sits in decides whether the toolbar shows, and for which block. */
  private void update_active () {
    Gtk.TextIter cursor;
    buffer.get_iter_at_mark (out cursor, buffer.get_insert ());
    int line = cursor.get_line ();
    active = -1;
    for (int i = 0; i < conflicts.length; i++) {
      if (line >= conflicts[i].start_line && line <= conflicts[i].end_line) {
        active = i;
        break;
      }
    }
    toolbar.visible = active >= 0;
    if (active >= 0) {
      var c = conflicts[active];
      current_button.label = _("Use %s").printf (c.current_label != "" ? c.current_label : _("current"));
      incoming_button.label = _("Use %s").printf (c.incoming_label != "" ? c.incoming_label : _("incoming"));
    }
  }

  private Gtk.Button action (string label, string side) {
    var button = new Gtk.Button.with_label (label) { has_frame = false };
    button.add_css_class ("compact-control");
    button.clicked.connect (() => {
      if (active < 0) {
        return;
      }
      try {
        accept (active, side);
      } catch (Error e) {
        Logger.warn ("conflict accept: %s".printf (e.message));
      }
    });
    return button;
  }
}
