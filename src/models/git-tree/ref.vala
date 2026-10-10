/**
 * `GitTree`: the repository's history as the Git view draws it — commits
 * from `git log` (Log), laid out into lanes (Graph), plus the working
 * tree as a row of its own (WorkingRow). Its own namespace, apart from
 * GitScope: nothing here is about one path or the index, all of it is
 * about the graph.
 */
namespace GitTree {
  public enum RefKind {
    LOCAL,
    REMOTE,
    TAG;
  }

  /** One decoration on a commit: a branch (local or remote) or a tag. */
  public class Ref : Object {
    /** Short: "main", "origin/main", "v0.2.0". */
    public string name { get; construct; }
    public RefKind kind { get; construct; }
    /** Whether HEAD points at this branch — the one the user is on. */
    public bool is_head { get; construct; }

    public Ref (string name, RefKind kind, bool is_head = false) {
      Object (name: name, kind: kind, is_head: is_head);
    }

    /**
     * Parses `git log --decorate=full`'s own `%D`: "HEAD -> refs/heads/main,
     * refs/remotes/origin/main, tag: refs/tags/v0.2.0", sorted (see compare()). A bare "HEAD" (detached)
     * is no ref at all; neither is a remote's own `HEAD` ("refs/remotes/
     * origin/HEAD -> refs/remotes/origin/main", the clone's note of the
     * remote's default branch, which no client lists); `refs/stash` and
     * anything else outside heads/remotes/tags is skipped.
     */
    public static GenericArray<Ref> parse (string decorations) {
      var refs = new GenericArray<Ref> ();
      foreach (var raw in decorations.split (",")) {
        var item = raw.strip ();
        bool is_head = false;
        if (item.has_prefix ("HEAD -> ")) {
          is_head = true;
          item = item.substring ("HEAD -> ".length);
        }
        if (item.has_prefix ("tag: ")) {
          item = item.substring ("tag: ".length);
        }
        var parsed = from_full_name (item, is_head);
        if (parsed != null) {
          refs.add (parsed);
        }
      }
      refs.sort_with_data (compare);
      return refs;
    }

    /** The branch HEAD is on first, then local branches, remotes, tags — each group by name, so the chips read from "where I am" outward. */
    private static int compare (Ref a, Ref b) {
      if (a.is_head != b.is_head) {
        return a.is_head ? -1 : 1;
      }
      if (a.kind != b.kind) {
        return a.kind < b.kind ? -1 : 1;
      }
      return strcmp (a.name, b.name);
    }

    private static Ref? from_full_name (string full_name, bool is_head) {
      if (full_name.has_prefix ("refs/heads/")) {
        return new Ref (full_name.substring ("refs/heads/".length), RefKind.LOCAL, is_head);
      }
      if (full_name.has_prefix ("refs/remotes/")) {
        var name = full_name.substring ("refs/remotes/".length);
        if (name.has_suffix ("/HEAD") || name.contains ("/HEAD -> ")) {
          return null;
        }
        return new Ref (name, RefKind.REMOTE);
      }
      if (full_name.has_prefix ("refs/tags/")) {
        return new Ref (full_name.substring ("refs/tags/".length), RefKind.TAG);
      }
      return null;
    }
  }
}
