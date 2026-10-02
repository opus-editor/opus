namespace CommandBar {
  /**
   * Opens and closes the Command Bar and keeps the right provider on
   * duty — VS Code's own QuickAccessController, minus the DI: on every
   * text change the {@link Registry} is asked again, and when the
   * answer changes (a `>` typed at the start, or deleted) the current
   * picker is retired and a fresh one, carrying the same text, goes to
   * the new provider. A retired picker is cancelled, then closed, so a
   * provider's own teardown sees both.
   *
   * `opened` fires for every picker, including the replacement ones;
   * `closed` only for a real close. The view binds through these, not
   * through Picker.closed, so a provider switch never looks like a
   * dismissal.
   */
  public class Router : Object {
    private Registry registry;
    private Cancellable? cancellable = null;

    public Picker? picker { get; private set; default = null; }
    public IProvider? provider { get; private set; default = null; }

    public bool is_open {
      get { return picker != null; }
    }

    public signal void opened (Picker picker);
    public signal void closed ();

    public Router (Registry registry) {
      this.registry = registry;
    }

    /** A no-op while already open, or when no provider claims `initial_text` (an empty registry — nothing to show). */
    public void open (string initial_text = "") {
      if (picker != null) {
        return;
      }
      var resolved = registry.resolve (initial_text);
      if (resolved == null) {
        return;
      }
      start (resolved, initial_text);
    }

    public void close () {
      if (picker == null) {
        return;
      }
      retire ();
      closed ();
    }

    private void start (IProvider next_provider, string text) {
      provider = next_provider;
      var next_picker = new Picker (next_provider.prefix);
      next_picker.placeholder = next_provider.placeholder;
      next_picker.text = text;
      picker = next_picker;
      cancellable = new Cancellable ();

      next_picker.notify["text"].connect (on_text_changed);
      opened (next_picker);
      next_provider.provide (next_picker, cancellable);
    }

    private void retire () {
      var retired = picker;
      retired.notify["text"].disconnect (on_text_changed);
      cancellable.cancel ();
      picker = null;
      provider = null;
      cancellable = null;
      retired.close ();
    }

    private void on_text_changed () {
      var text = picker.text;
      var next = registry.resolve (text);
      if (next == null || next == provider) {
        return;
      }
      retire ();
      start (next, text);
    }
  }
}
