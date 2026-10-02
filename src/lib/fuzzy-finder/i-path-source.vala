namespace Opus.FuzzyFinder {
  /**
   * Something that produces the candidate paths an {@link Index} gets
   * filled with: root-relative, "/"-separated, handed over in batches on
   * the main loop so the first ones can be searched while the rest are
   * still being found. {@link DirectoryWalker} is the one this library
   * ships; a host can plug in its own (a VCS's own file listing, say)
   * without the engine knowing where the paths came from.
   */
  public interface IPathSource : Object {
    /** The next batch of paths found, root-relative. Emitted on the main loop, in discovery order. */
    public signal void batch (string[] relative_paths);

    /** The listing ended — every path was reported, or `cancelled` cut it short. Emitted on the main loop, exactly once per start(). */
    public signal void finished (bool cancelled);

    /** Begins producing paths in the background. A second call is ignored — construct another source for another listing. */
    public abstract void start (Cancellable cancellable);
  }
}
