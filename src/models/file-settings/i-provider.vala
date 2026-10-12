/**
 * Per-file editor settings (indentation, line ending, charset, the save
 * rules) from a source in the workspace — the
 * `.editorconfig` plugin is the one so far. Resolved when the host needs
 * them (building a tab's editor, saving), never pushed: a provider that
 * learns of a change just answers differently next time.
 */
namespace FileSettings {
  public interface IProvider : Object, IWorkspaceExtension {
    /** What this provider says about the file at `path` (absolute); every field null when nothing. */
    public abstract Values settings_for (string path);

    /** settings_for() may answer differently now — a source was rewritten. Emit on the main loop. */
    public signal void changed ();
  }
}
