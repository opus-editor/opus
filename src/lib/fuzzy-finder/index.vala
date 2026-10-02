namespace Opus.FuzzyFinder {
  /**
   * A flat, in-memory list of candidate strings and the one operation
   * that matters: rank them against a {@link Query}, cheapest rejection
   * first (character bitset, then ordered subsequence, then the real
   * {@link Scorer}), keeping only the top `max_results`.
   *
   * No trie or sorted structure on purpose: a casefolded flat array
   * plus these prefilters is what VS Code and Zed both run per keystroke.
   * The one memory it keeps is which candidates survived the previous
   * search, so a query that merely grows (`fo` -> `foo`) only re-scores
   * those (nucleo's own "Update" vs "Rescore" distinction).
   */
  public class Index : Object {
    private class Candidate {
      public string text;
      public string lower;
      public uint64 bag;

      public Candidate (string text) {
        this.text = text;
        lower = text.casefold ();
        bag = Scorer.char_bag_of (lower);
      }
    }

    private const uint CANCEL_CHECK_INTERVAL = 1000;

    private GenericArray<Candidate> candidates = new GenericArray<Candidate> ();
    private Query? last_query = null;
    private uint[] last_survivors = {};

    public uint size {
      get { return candidates.length; }
    }

    public string text_at (uint index) {
      return candidates[index].text;
    }

    public void set_candidates (string[] texts) {
      candidates = new GenericArray<Candidate> ();
      append (texts);
    }

    public void append (string[] texts) {
      foreach (var text in texts) {
        candidates.add (new Candidate (text));
      }
      forget_survivors ();
    }

    /**
     * Drops every candidate that is a direct child of `directory`
     * (`"src/"` → `src/App.vala`, not `src/models/x.vala`; `""` → the
     * root's own files) and appends `texts` — how one directory's own
     * listing gets refreshed in place without touching anything deeper
     * or re-walking everything else.
     */
    public void replace_direct_children (string directory, string[] texts) {
      var kept = new GenericArray<Candidate> ();
      for (uint i = 0; i < candidates.length; i++) {
        var candidate = candidates[i];
        if (!is_direct_child (candidate.text, directory)) {
          kept.add (candidate);
        }
      }
      candidates = kept;
      append (texts);
    }

    private static bool is_direct_child (string text, string directory) {
      if (!text.has_prefix (directory)) {
        return false;
      }
      return !text.substring (directory.length).contains ("/");
    }

    /** Empty for an empty query — a default list is the caller's own idea of what to show then, never "everything". Returns null if cancelled part-way. */
    public Match[]? search (Query query, uint max_results, Cancellable? cancellable = null) {
      if (query.is_empty || max_results == 0) {
        forget_survivors ();
        return {};
      }

      bool reuse_survivors = last_query != null && query.extends (last_query)
        && !(query.contains_separator && !last_query.contains_separator);

      var matches = new GenericArray<Match> ();
      uint[] survivors = {};
      uint checked = 0;

      uint base_count = reuse_survivors ? last_survivors.length : candidates.length;
      for (uint i = 0; i < base_count; i++) {
        if (++checked % CANCEL_CHECK_INTERVAL == 0 && cancellable != null && cancellable.is_cancelled ()) {
          return null;
        }

        uint candidate_index = reuse_survivors ? last_survivors[i] : i;
        var candidate = candidates[candidate_index];
        if ((candidate.bag & query.char_bag) != query.char_bag) {
          continue;
        }
        if (!Scorer.contains_subsequence (candidate.lower, query.normalized_lower)) {
          continue;
        }

        int score;
        int[] ranges;
        if (!Scorer.score (candidate.text, candidate.lower, query, out score, out ranges)) {
          continue;
        }
        survivors += candidate_index;
        matches.add (new Match (candidate_index, score, ranges));
      }

      last_query = query;
      last_survivors = survivors;

      matches.sort_with_data ((a, b) => compare (a, b));
      uint count = uint.min (max_results, matches.length);
      var result = new Match[count];
      for (uint i = 0; i < count; i++) {
        result[i] = matches[i];
      }
      return result;
    }

    private int compare (Match a, Match b) {
      if (a.score != b.score) {
        return b.score - a.score;
      }
      var text_a = candidates[a.candidate_index].text;
      var text_b = candidates[b.candidate_index].text;
      if (text_a.length != text_b.length) {
        return text_a.length - text_b.length;
      }
      return strcmp (text_a, text_b);
    }

    private void forget_survivors () {
      last_query = null;
      last_survivors = {};
    }
  }
}
