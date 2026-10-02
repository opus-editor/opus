namespace Opus.FuzzyFinder {
  /** One ranked hit from {@link Index.search}. `ranges` are [start, end) pairs of Unicode character offsets into the candidate's text — the view converts to whatever offsets its rendering needs, once. */
  public class Match : Object {
    public uint candidate_index;
    public int score;
    public int[] ranges;

    public Match (uint candidate_index, int score, owned int[] ranges) {
      this.candidate_index = candidate_index;
      this.score = score;
      this.ranges = (owned) ranges;
    }
  }
}
