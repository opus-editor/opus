/**
 * How one text indents, every source already weighed — what the editor
 * applies, and what the Document Properties pane shows. Resolved by
 * {@link resolve}: the document's own picks first, then the folder's
 * .editorconfig, then settings.json for the language, then the editor's
 * own defaults (spaces, four of them, indenting by itself).
 */
public class Indentation : Object {
  /** Columns per indent level. */
  public int size { get; construct; }
  /** Whether Tab inserts spaces rather than a tab character. */
  public bool insert_spaces { get; construct; }
  /** How wide a literal tab renders: picked, or the folder's or settings' `tab_width`, else `size`. */
  public int tab_width { get; construct; }
  /** Whether `tab_width` is only `size` again, nothing having said otherwise. */
  public bool tab_width_from_size { get; construct; }
  /** Whether Enter indents at all — the new line taking the last one's indentation and what the syntax adds, and a closer typed pulling its line out. */
  public bool auto_indent { get; construct; }

  public Indentation (int size, bool insert_spaces, int tab_width, bool tab_width_from_size, bool auto_indent) {
    Object (size: size, insert_spaces: insert_spaces, tab_width: tab_width, tab_width_from_size: tab_width_from_size, auto_indent: auto_indent);
  }

  /** `file` is the folder's word on the text, every field null where it has none; `document` carries the picks made by hand, none for a text that has no document (a diff). */
  public static Indentation resolve (FileSettings.Values file, UserSettings settings, string? language, Document? document = null) {
    var spaces_pick = document == null ? Document.Override.NONE : document.insert_spaces_override;
    var auto_pick = document == null ? Document.Override.NONE : document.auto_indent_override;
    int size_pick = document == null ? 0 : document.indent_size_override;
    int width_pick = document == null ? 0 : document.tab_width_override;

    int size = size_pick > 0 ? size_pick : file.indent_size ?? settings.indent_size_for (language);
    bool insert_spaces = spaces_pick != Document.Override.NONE ? spaces_pick == Document.Override.ON : file.insert_spaces ?? settings.insert_spaces_for (language);
    bool auto_indent = auto_pick != Document.Override.NONE ? auto_pick == Document.Override.ON : settings.auto_indent_for (language);
    int? tab_width = file.tab_width ?? settings.tab_width_for (language);
    if (width_pick > 0) {
      tab_width = width_pick;
    }
    return new Indentation (size, insert_spaces, tab_width == null ? size : (int) tab_width, tab_width == null, auto_indent);
  }
}
