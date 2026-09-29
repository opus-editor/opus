/** One file's own live matches, grouped into display blocks — see FindInFilesBlock. */
public class FindInFilesFileResult : Object {
  public string path;
  public GenericArray<FindInFilesBlock> blocks = new GenericArray<FindInFilesBlock> ();
  public int match_count;
}
