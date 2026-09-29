/**
 * FindInFilesReplace.run()'s own outcome: which files it left untouched
 * (modified on disk after the search that produced the query's own
 * FindInFilesResult ran, so what's shown for them can't be trusted to
 * still be accurate — see FindInFilesResult.searched_at's own doc
 * comment) and, for every file it *did* write, exactly where each
 * replacement landed in that file's new content. FindResults uses the
 * latter to re-highlight the real, just-written text without
 * re-searching for it — see FindInFilesReplace's own doc comment for
 * why that's both correct and cheap to do.
 */
public class FindInFilesReplaceResult : Object {
  public GenericArray<string> skipped_paths = new GenericArray<string> ();

  /** path -> every replacement's own position in that file's new content, in file order. Absent for a path in skipped_paths (nothing was written there). */
  public HashTable<string, GenericArray<FindInFilesMatch>> new_matches_by_path =
    new HashTable<string, GenericArray<FindInFilesMatch>> (str_hash, str_equal);
}
