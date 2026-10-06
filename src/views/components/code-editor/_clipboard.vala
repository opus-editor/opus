/**
 * Copy/Cut/Paste against the system clipboard, multi-cursor aware: Copy
 * joins every cursor's selection with "\n", and a later Paste with the
 * same number of cursors hands each cursor its own piece back
 * (distributed paste, mirroring VS Code's real
 * PasteOperation._distributePasteToCursors in
 * cursorTypeEditOperations.ts) — either because the clipboard still
 * holds exactly what was last copied from here, or because the pasted
 * text simply has one line per cursor.
 *
 * The one genuinely-view thing here is text_view.get_clipboard(); the
 * edits themselves go through CodeEditorCursors like any other command.
 */
public class CodeEditorClipboard : Object {
  private CodeEditorSourceView text_view;
  private CodeEditorCursors cursors;

  // Ties a same-session Paste's per-cursor pieces to whether the
  // clipboard's content still matches what was last copied from here.
  // Static: the clipboard is one, and a copy in one tab's editor is
  // pasted in another's.
  private static string? last_clipboard_text = null;
  private static string[]? last_clipboard_pieces = null;

  public CodeEditorClipboard (CodeEditorSourceView text_view, CodeEditorCursors cursors) {
    this.text_view = text_view;
    this.cursors = cursors;
  }

  /** A no-op with no selection on the primary cursor — same as GTK's own Copy. */
  public void copy () {
    write_selection ();
  }

  public void cut () {
    if (write_selection ()) {
      cursors.delete_selections ();
    }
  }

  public void paste () {
    paste_async.begin (cursors.cursors);
  }

  private bool write_selection () {
    if (cursors.cursors.primary.is_empty) {
      return false;
    }

    var pieces = cursors.selected_texts ();
    string joined = string.joinv ("\n", pieces);
    text_view.get_clipboard ().set_text (joined);
    last_clipboard_text = joined;
    last_clipboard_pieces = pieces.length > 1 ? pieces : null;
    return true;
  }

  /** `target` is whichever cursor set was bound when Paste was pressed — if a rebind happens during the async clipboard read, the paste must land nowhere rather than in a cursor set it wasn't meant for. */
  private async void paste_async (CursorCollection target) {
    string? text = null;
    try {
      text = yield text_view.get_clipboard ().read_text_async (null);
    } catch (Error e) {
      return;
    }
    if (text == null || text == "" || cursors.cursors != target) {
      return;
    }

    string[]? pieces = distributed_pieces (text, cursors.cursors.count);
    if (pieces == null) {
      cursors.insert_text (text);
    } else {
      cursors.paste_pieces (pieces);
    }
  }

  private string[]? distributed_pieces (string pasted_text, int cursor_count) {
    if (cursor_count == 1) {
      return null;
    }
    if (last_clipboard_pieces != null && pasted_text == last_clipboard_text && last_clipboard_pieces.length == cursor_count) {
      return last_clipboard_pieces;
    }

    string trimmed = pasted_text;
    if (trimmed.has_suffix ("\r\n")) {
      trimmed = trimmed.substring (0, trimmed.length - 2);
    } else if (trimmed.has_suffix ("\n") || trimmed.has_suffix ("\r")) {
      trimmed = trimmed.substring (0, trimmed.length - 1);
    }
    string[] lines = trimmed.split ("\n");
    return lines.length == cursor_count ? lines : null;
  }
}
