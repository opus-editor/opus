namespace Opus.Plugins.EditorConfig {
  /**
   * The FileSettings.IProvider the .editorconfig files make: resolved
   * per file when asked, with the parsed files cached by directory.
   * The workspace's own watcher empties the cache when a .editorconfig
   * is written, or any directory's listing changes (one may have been
   * created or removed); outside the linked folder nothing is watched,
   * so a `~/.editorconfig` edit counts from the next link on.
   */
  public class Provider : Object, IWorkspaceExtension, FileSettings.IProvider {
    public WorkspaceContext context { get; set; }

    private class Entry : Object {
      public ConfigFile? file;
      public Entry (ConfigFile? file) { this.file = file; }
    }
    private HashTable<string, Entry> cache = new HashTable<string, Entry> (str_hash, str_equal);

    public Provider (WorkspaceContext context) {
      Object (context: context);
    }

    public void activate () {
      context.directory_changed.connect (on_directory_changed);
      context.file_content_changed.connect (on_file_content_changed);
    }

    public void deactivate () {
      context.directory_changed.disconnect (on_directory_changed);
      context.file_content_changed.disconnect (on_file_content_changed);
      cache.remove_all ();
    }

    public FileSettings.Values settings_for (string path) {
      var resolved = Hierarchy.for_file (path, cached).resolve (path);
      var values = new FileSettings.Values ();
      values.indent_size = resolved.indent_size ();
      values.insert_spaces = resolved.insert_spaces ();
      values.line_ending = resolved.end_of_line ();
      values.trim_trailing_whitespace = resolved.trim_trailing_whitespace ();
      values.insert_final_newline = resolved.insert_final_newline ();
      return values;
    }

    private ConfigFile? cached (string directory) {
      var entry = cache[directory];
      if (entry == null) {
        entry = new Entry (ConfigFile.in_directory (directory));
        cache[directory] = entry;
      }
      return entry.file;
    }

    private void on_directory_changed (string path) {
      cache.remove_all ();
    }

    private void on_file_content_changed (string path) {
      if (Path.get_basename (path) == ConfigFile.NAME) {
        cache.remove_all ();
      }
    }
  }
}
