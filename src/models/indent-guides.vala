/**
 * Pure line-indentation analysis over a slice of text: how many vertical
 * guide levels each line shows, and which contiguous block of lines shares
 * the guide level the cursor currently sits at — the two pieces {@link
 * CodeEditorSourceView} needs to paint VS Code-style indent
 * guides, ported from its own real implementation
 * (`guidesTextModelPart.ts`/`utils.ts`) with two deliberate simplifications:
 *
 * - No "offside" (Python/YAML-style, no closing brace) language distinction
 *   for the one case that needs it — a blank line sitting exactly at a
 *   dedent. GtkSourceView's `.lang` files carry no such metadata to key
 *   off of. Always takes the non-offside branch; worst case a blank line
 *   at a dedent shows one guide level too many.
 * - A single `indent_size` serves both roles VS Code splits into `tabSize`
 *   and `indentSize` — matches the common case where they're equal, and
 *   is what {@link EditorConfig.indent_size_for} already produces.
 *
 * `active_guide` ports VS Code's own `getActiveIndentGuide`
 * (`guidesTextModelPart.ts:41`) faithfully — control flow included, not
 * just the visible effect: picking the cursor's own line's level as the
 * target unconditionally is wrong the moment that line opens a block
 * (e.g. `def foo`) — every sibling `def` in the same class shares that
 * same, uninterrupted outer guide level, so they'd all get highlighted
 * as one block. VS Code retargets a scope-opening/closing line to the
 * block it opens/closes for exactly this reason, see that method's own
 * doc comment below. Simplified only in *how* each line's own level is
 * looked up: VS Code computes it lazily, walking outward for the nearest
 * non-blank neighbor on demand (its own document has no bound on size);
 * this class already has every line's level precomputed in `all_levels`
 * by the time `active_guide` runs, so that lookup is just an array index.
 */
public class IndentGuides : Object {
  private string[] lines;
  private int indent_size;
  private int[] all_levels;

  public IndentGuides (string text, int indent_size) {
    // string.split("\n") special-cases "" to a zero-length array
    // rather than one empty line (confirmed directly) — every other
    // method here assumes at least one line exists, matching a real
    // Gtk.TextBuffer, which always has one even when totally empty.
    var split = text.split ("\n");
    this.lines = split.length > 0 ? split : new string[] { "" };
    this.indent_size = indent_size;
    this.all_levels = compute_all_levels ();
  }

  /** 0-based, inclusive of both ends, clamped to the text's own line range. */
  public int[] levels_for_lines (int start_line, int end_line) {
    int clamped_start = start_line.clamp (0, lines.length - 1);
    int clamped_end = end_line.clamp (0, lines.length - 1);

    var result = new int[clamped_end - clamped_start + 1];
    for (int i = 0; i < result.length; i++) {
      result[i] = all_levels[clamped_start + i];
    }
    return result;
  }

  /**
   * 0-based cursor line. `level == 0` (`start_line`/`end_line == -1`)
   * means the cursor isn't inside any indented block.
   *
   * The cursor's own line's level isn't always the target: a line that
   * *opens* a scope (the line right below it sits exactly one level
   * deeper — e.g. `def foo`, `if x:`) retargets to that deeper, child
   * level instead, and the range starts from that child line, not the
   * opener itself — otherwise every sibling block at the same outer
   * level (every `def` in a class, say) would share one contiguous
   * outer guide and get highlighted together as if they were one block.
   * A line that *closes* a scope (the line above it is one level
   * deeper — e.g. a dedent, or a closing `end`) mirrors this the other
   * way. Only a plain line — neither opening nor closing anything —
   * uses its own level directly, and only then can `level` come back
   * `0` (an unindented line with no adjacent deeper scope either way).
   */
  public void active_guide (int cursor_line, out int start_line, out int end_line, out int level) {
    if (cursor_line < 0 || cursor_line >= lines.length) {
      start_line = -1;
      end_line = -1;
      level = 0;
      return;
    }

    int initial_level = all_levels[cursor_line];
    bool has_above = cursor_line > 0;
    bool has_below = cursor_line < lines.length - 1;
    int above_level = has_above ? all_levels[cursor_line - 1] : -1;
    int below_level = has_below ? all_levels[cursor_line + 1] : -1;

    int start = cursor_line;
    int end = cursor_line;
    int target_level = initial_level;
    bool extend_up = true;
    bool extend_down = true;

    if (has_below && below_level == initial_level + 1) {
      extend_up = false;
      start = cursor_line + 1;
      end = cursor_line + 1;
      target_level = below_level;
    } else if (has_above && above_level - 1 == initial_level) {
      extend_down = false;
      start = cursor_line - 1;
      end = cursor_line - 1;
      target_level = above_level;
    } else if (initial_level == 0) {
      start_line = -1;
      end_line = -1;
      level = 0;
      return;
    }

    if (extend_up) {
      int l = start - 1;
      while (l >= 0 && all_levels[l] >= target_level) {
        start = l;
        l--;
      }
    }
    if (extend_down) {
      int l = end + 1;
      while (l < lines.length && all_levels[l] >= target_level) {
        end = l;
        l++;
      }
    }

    start_line = start;
    end_line = end;
    level = target_level;
  }

  private int[] compute_all_levels () {
    var result = new int[lines.length];

    int above_index = -2; // -2 = not computed yet, -1 = none found in range
    int above_indent = -1;
    int below_index = -2;
    int below_indent = -1;

    for (int line = 0; line < lines.length; line++) {
      int current_indent = compute_indent_level (lines[line]);

      if (current_indent >= 0) {
        above_index = line;
        above_indent = current_indent;
        result[line] = ceil_div (current_indent, indent_size);
        continue;
      }

      if (above_index == -2) {
        above_index = -1;
        above_indent = -1;
        for (int l = line - 1; l >= 0; l--) {
          int indent = compute_indent_level (lines[l]);
          if (indent >= 0) {
            above_index = l;
            above_indent = indent;
            break;
          }
        }
      }

      if (below_index != -1 && (below_index == -2 || below_index < line)) {
        below_index = -1;
        below_indent = -1;
        for (int l = line + 1; l < lines.length; l++) {
          int indent = compute_indent_level (lines[l]);
          if (indent >= 0) {
            below_index = l;
            below_indent = indent;
            break;
          }
        }
      }

      result[line] = indent_level_for_whitespace_line (above_indent, below_indent);
    }

    return result;
  }

  /** Ported from `_getIndentLevelForWhitespaceLine` — the non-offside branch only, see this class's own doc comment. */
  private int indent_level_for_whitespace_line (int above_indent, int below_indent) {
    if (above_indent == -1 || below_indent == -1) {
      return 0; // top or bottom of the available text
    } else if (above_indent < below_indent) {
      return 1 + above_indent / indent_size; // inside the block that opened above
    } else if (above_indent == below_indent) {
      return ceil_div (below_indent, indent_size); // between two same-depth regions
    } else {
      return 1 + below_indent / indent_size; // inside the block that ends below
    }
  }

  /** Ported from `computeIndentLevel`: walks leading whitespace, space = +1, tab = round up to the next `indent_size` multiple. `-1` if the line is entirely whitespace. */
  private int compute_indent_level (string line) {
    int indent = 0;
    int i = 0;
    int n = line.length;

    while (i < n) {
      char c = line[i];
      if (c == ' ') {
        indent++;
      } else if (c == '\t') {
        indent = indent - indent % indent_size + indent_size;
      } else {
        break;
      }
      i++;
    }

    if (i == n) {
      return -1;
    }
    return indent;
  }

  private static int ceil_div (int a, int b) {
    return (a + b - 1) / b;
  }
}
