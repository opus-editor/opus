namespace CommandBar {
  /**
   * What the Command Bar lists for one prefix — the parallel of VS
   * Code's IQuickAccessProvider: `""` is the default (file search), a
   * future `>` lists commands. An IWorkspaceExtension so a plugin can
   * contribute one through the same Opus.Plugins.WorkspaceExtensions
   * path FileDecoration.IProvider already uses; the built-in file
   * provider implements it the same way, so there is one kind of
   * provider, not two.
   *
   * provide() is called once per opening with a fresh {@link Picker}:
   * connect to its `filter_changed`/`accepted`, fill `items` as results
   * arrive, and stop touching it once `cancellable` is cancelled or its
   * `closed` fired — the Router cancels, then closes, in that order.
   */
  public interface IProvider : Object, IWorkspaceExtension {
    public abstract string prefix { owned get; }
    public abstract string placeholder { owned get; }
    public abstract void provide (Picker picker, Cancellable cancellable);
  }
}
