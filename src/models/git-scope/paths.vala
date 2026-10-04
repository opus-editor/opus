/**
 * `GitScope`: asking git about one part of a workspace instead of all of
 * it. A scope is the single path a batch of changes is narrowed down to —
 * a directory, or one file — and the only part of what was known before
 * that the answer replaces.
 */
namespace GitScope {
  public class Paths : Object {
    public static bool is_at_or_under (string path, string scope) {
      return path == scope || path.has_prefix (scope + "/");
    }

    /** The deepest path that holds both — what two pending scopes widen to. */
    public static string common_ancestor (string a, string b) {
      var ancestor = a;
      while (!is_at_or_under (b, ancestor)) {
        var parent = Path.get_dirname (ancestor);
        if (parent == ancestor) {
          break; // the filesystem root holds everything
        }
        ancestor = parent;
      }
      return ancestor;
    }
  }
}
