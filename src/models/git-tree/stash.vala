namespace GitTree {
  /**
   * One `git stash` entry: a commit of its own, parked outside every
   * branch, whose first parent is the commit it was taken on (`base`).
   * Drawn as a dashed row right above that base, the way most clients
   * do; its other parents (the index, the untracked files) are not.
   */
  public class Stash : Object {
    public string hash { get; construct; }
    public string base_hash { get; construct; }
    /** "stash@{0}", "stash@{1}", … — newest first, as `git stash list` numbers them. */
    public string name { get; construct; }
    /** The branch it was taken on, "" when the subject didn't say. */
    public string branch { get; construct; }
    /** The subject minus git's own "WIP on <branch>: " / "On <branch>: " prefix. */
    public string message { get; construct; }
    public int64 timestamp { get; construct; }

    public Stash (string hash, string base_hash, string name, string branch, string message, int64 timestamp) {
      Object (hash: hash, base_hash: base_hash, name: name, branch: branch, message: message, timestamp: timestamp);
    }

    /** Splits git's own stash subject: "WIP on main: 1a2b3c subject" or "On main: my note". */
    public static void split_subject (string subject, out string branch, out string message) {
      branch = "";
      message = subject;
      string rest;
      if (subject.has_prefix ("WIP on ")) {
        rest = subject.substring ("WIP on ".length);
      } else if (subject.has_prefix ("On ")) {
        rest = subject.substring ("On ".length);
      } else {
        return;
      }
      int colon = rest.index_of (": ");
      if (colon < 0) {
        return;
      }
      branch = rest.substring (0, colon);
      message = rest.substring (colon + 2);
    }
  }
}
