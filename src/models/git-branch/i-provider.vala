/**
 * Prerequisite-first, same rule as FileDecoration.IProvider — see
 * docs/DECISIONS.md and src/plugins/AGENTS.md.
 */
namespace GitBranch {
  public interface IProvider : Object, IWorkspaceExtension {
    /** The branch the workspace is on, a short commit when HEAD is detached, null outside a repository — answered from the last read, never blocking. */
    public abstract string? current_branch ();

    /** current_branch()'s answer changed — emitted on the main loop. */
    public signal void branch_changed ();
  }
}
