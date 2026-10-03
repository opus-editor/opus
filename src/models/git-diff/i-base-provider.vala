/**
 * Prerequisite-first, same rule as FileDecoration.IProvider — see
 * docs/DECISIONS.md and src/plugins/CLAUDE.md.
 */
namespace GitDiff {
  public interface IBaseProvider : Object, IWorkspaceExtension {
    /** `path` absolute. See Bases's own doc comment for what a null field means. */
    public abstract async Bases? bases_for (string path);

    /** A path's bases may have changed (commit/stage/checkout/merge) — null path means "everything, re-check whatever's currently tracked." */
    public signal void bases_changed (string? path);
  }
}
