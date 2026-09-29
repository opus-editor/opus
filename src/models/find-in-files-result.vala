/** A completed FindInFilesSearch.run() — every file with at least one match, plus the query that produced it (so a renderer can label itself without the caller threading the query through separately). */
public class FindInFilesResult : Object {
  public FindInFilesQuery query;
  public GenericArray<FindInFilesFileResult> files = new GenericArray<FindInFilesFileResult> ();
  public int total_match_count;

  /** The context_lines run() was actually called with — a renderer uses this (not a live, possibly-since-changed control) to decide whether blocks within the same file need a blank line between them at all, same as VS Code's own Search Editor: with context, a blank line marks a real gap in the file; with none, every match is already a flat list, so this is 0 in the common case. */
  public int context_lines;

  /** Hit FindInFilesSearch's own MAX_MATCHES cap and stopped early — the walk didn't cover the whole tree. */
  public bool truncated;

  /** When run() started walking — FindInFilesReplace's own safety check compares each file's real mtime against this before writing to it, so a file edited after the search ran (and therefore not reflected in what's shown here) is left untouched instead of silently overwritten. */
  public DateTime searched_at;

  public int file_count { get { return (int) files.length; } }
}
