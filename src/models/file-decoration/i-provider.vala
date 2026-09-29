/**
 * The parallel of `vscode.FileDecorationProvider`, idiomatic GObject and
 * synchronous by design — VS Code's own equivalent is async only because
 * of its extension-host process boundary; an in-process provider that
 * computes in the background (git's own subprocess) just answers from its
 * last snapshot.
 */
namespace FileDecoration {
  public interface IProvider : Object, IWorkspaceExtension {
    /**
     * Every path this provider currently decorates — the full current
     * set, absolute paths, not a delta. Files and/or directories. Called
     * by FileDecoration.Registry on activate() and after every
     * decorations_changed.
     */
    public abstract HashTable<string, State> current_decorations ();

    /** The set returned by current_decorations() changed — emit on the main loop. */
    public signal void decorations_changed ();
  }
}
