/**
 * One contiguous run of a file's own lines shown together — a matched
 * line plus its own context lines before/after, merged with any
 * neighboring match's own context window once they touch or overlap
 * (see FindInFilesSearch.merge_into_blocks()) so the same line is never
 * shown twice within one file.
 */
public class FindInFilesBlock : Object {
  /** 1-based, inclusive — `lines[0]` is this line. */
  public int start_line;

  /** Raw text, `lines[i]` is line `start_line + i`. */
  public string[] lines;

  /** Every match landing on one of `lines`, in document order. */
  public GenericArray<FindInFilesMatch> matches = new GenericArray<FindInFilesMatch> ();
}
