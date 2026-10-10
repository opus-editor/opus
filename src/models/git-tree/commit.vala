namespace GitTree {
  public class Commit : Object {
    public string hash { get; construct; }
    /** Oldest-first as git lists them: the first is what the commit's own lane continues into. */
    public string[] parents { get; construct; }
    public string author { get; construct; }
    public string email { get; construct; }
    /** Seconds since the epoch, the author date. */
    public int64 timestamp { get; construct; }
    public string subject { get; construct; }
    /** The body's first non-empty line, "" without one — what the row shows dimmed after the subject. */
    public string body_first_line { get; construct; }
    /** The whole body after the subject, trimmed, "" without one. */
    public string body { get; construct; default = ""; }
    public GenericArray<Ref> refs { get; construct; }
    /** Whether HEAD is here — through a branch (one of `refs` has is_head) or detached. */
    public bool is_head { get; construct; }

    public Commit (string hash, string[] parents, string author, string email, int64 timestamp, string subject, string body_first_line, GenericArray<Ref> refs, bool is_head, string body = "") {
      Object (hash: hash, parents: parents, author: author, email: email, timestamp: timestamp, subject: subject, body_first_line: body_first_line, refs: refs, is_head: is_head, body: body);
    }

    /** Subject and body as one message, the way the commit box would show it. */
    public string message {
      owned get { return body == "" ? subject : "%s\n\n%s".printf (subject, body); }
    }

    /** The author date as DD/MM/YY, in local time. */
    public string date_label {
      owned get { return new DateTime.from_unix_local (timestamp).format ("%d/%m/%y"); }
    }

    public string short_hash {
      owned get { return hash.substring (0, int.min (7, hash.length)); }
    }
  }
}
