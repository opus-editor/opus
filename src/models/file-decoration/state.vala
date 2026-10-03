/**
 * A file's (or folder's) resolved decoration — a color-coded tone plus
 * tooltip text some FileDecoration.IProvider attaches to a path. Plain
 * data, no Gtk: a View decides what a given Tone actually looks like (see
 * ExplorerPaneTreeRow.update_decoration()).
 *
 * Named `State`, not a bare `FileDecoration` repeating this namespace's
 * own name — a namespace and a class sharing one name causes a real
 * collision in this codebase (see ExplorerPane's own doc comment on
 * FileTree). Every reference from outside this namespace spells the full
 * path (`FileDecoration.State`), never a bare `using` shortcut — same
 * discipline `views/CLAUDE.md` already holds View namespaces to.
 */
namespace FileDecoration {
  public class State : Object {
    public Tone tone { get; construct; }
    /** Row tooltip ("Modified", "Renamed"…). */
    public string? tooltip { get; construct; default = null; }
    /** Tooltip an ancestor folder shows when this is the winning bubbled child ("Contains modified files"). */
    public string? bubble_tooltip { get; construct; default = null; }
    /** Whether ancestor folders inherit this tone — VS Code's `propagate`. False for e.g. "open in a tab". */
    public bool propagate { get; construct; default = true; }
    /** Whether everything beneath this path shows it too, unless it has a decoration of its own — an ignored folder mutes its whole subtree. */
    public bool covers_descendants { get; construct; default = false; }

    public State (Tone tone, string? tooltip, string? bubble_tooltip = null, bool propagate = true, bool covers_descendants = false) {
      Object (tone: tone, tooltip: tooltip, bubble_tooltip: bubble_tooltip, propagate: propagate, covers_descendants: covers_descendants);
    }
  }
}
