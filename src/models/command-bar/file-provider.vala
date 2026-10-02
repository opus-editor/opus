namespace CommandBar {
  /**
   * The default (no-prefix) provider: files under the linked folder.
   * Before anything is typed, the window's {@link RecentFiles}; once
   * typed, two tiers — recent files whose name matches, then every
   * other file ranked by Opus.FuzzyFinder — the same split VS Code's
   * own Go to File makes (COMMAND_BAR_FILE_SEARCH_PERFORMANCE.md).
   *
   * The file list is its own listing, not FileTree's: that tree is
   * one-level-lazy on purpose, search needs every path. At a repository
   * root the listing is GitFileList's — gitignored files never enter the
   * index at all; anywhere else (or should git itself fail) it is a
   * plain DirectoryWalker over everything. Every opening starts a fresh
   * listing in the background while the previous list keeps answering;
   * on the first opening there is no previous list, so the one being
   * filled answers instead, growing as batches land. Between listings,
   * a directory the explorer already watches gets its own immediate
   * children refreshed from `WorkspaceContext.directory_changed` — free,
   * since those watches exist anyway; directories it doesn't watch stay
   * as fresh as the last listing.
   */
  public class FileProvider : Object, IWorkspaceExtension, IProvider {
    private const uint MAX_RESULTS = 512;
    // VS Code's own TYPING_SEARCH_DELAY: while the list is still being
    // walked, a burst of keystrokes should cost one search, not five —
    // once it's warm, a search is cheap enough to run on every one.
    private const uint COLD_TYPING_DELAY_MS = 200;

    public WorkspaceContext context { get; set; }

    public string prefix {
      owned get { return ""; }
    }

    public string placeholder {
      owned get { return _("Search files by name"); }
    }

    private RecentFiles recent;
    private Opus.FuzzyFinder.Index? current = null;
    private Opus.FuzzyFinder.Index? staging = null;
    private Opus.FuzzyFinder.IPathSource? source = null;
    private Cancellable? source_cancellable = null;

    private Picker? picker = null;
    private Cancellable? picker_cancellable = null;
    private uint cold_timeout_id = 0;

    public FileProvider (WorkspaceContext context, RecentFiles recent) {
      Object (context: context);
      this.recent = recent;
    }

    public void activate () {
      context.directory_changed.connect (on_directory_changed);
    }

    public void deactivate () {
      context.directory_changed.disconnect (on_directory_changed);
      source_cancellable?.cancel ();
      detach_picker ();
    }

    public void provide (Picker picker, Cancellable cancellable) {
      this.picker = picker;
      picker_cancellable = cancellable;
      picker.filter_changed.connect (on_filter_changed);
      picker.accepted.connect (on_accepted);
      picker.closed.connect (on_picker_closed);

      refresh ();
      update ();
    }

    private void refresh () {
      if (source != null) {
        return; // the listing already under way will hand over when it finishes
      }
      source_cancellable = new Cancellable ();
      if (GitFileList.is_repository_root (context.root_path)) {
        var list = new GitFileList (context.root_path);
        list.failed.connect (on_git_failed);
        start_source (list);
      } else {
        start_source (new Opus.FuzzyFinder.DirectoryWalker (context.root_path));
      }
    }

    private void start_source (Opus.FuzzyFinder.IPathSource source) {
      this.source = source;
      staging = new Opus.FuzzyFinder.Index ();
      source.batch.connect (on_batch);
      source.finished.connect (on_source_finished);
      source.start (source_cancellable);
    }

    /** Git itself couldn't answer (missing from PATH, a broken repository) — the plain walk is the same list, just unfiltered. */
    private void on_git_failed () {
      start_source (new Opus.FuzzyFinder.DirectoryWalker (context.root_path));
    }

    private void on_batch (string[] relative_paths) {
      if (staging == null) {
        return;
      }
      staging.append (relative_paths);
      if (current == null) {
        schedule_cold_update ();
      }
    }

    private void on_source_finished (bool cancelled) {
      source = null;
      source_cancellable = null;
      if (cancelled) {
        staging = null;
        return;
      }
      current = staging;
      staging = null;
      cancel_cold_update ();
      update ();
    }

    private void on_filter_changed () {
      if (current == null) {
        schedule_cold_update ();
      } else {
        update ();
      }
    }

    private void schedule_cold_update () {
      cancel_cold_update ();
      cold_timeout_id = Timeout.add (COLD_TYPING_DELAY_MS, () => {
        cold_timeout_id = 0;
        update ();
        return Source.REMOVE;
      });
    }

    private void cancel_cold_update () {
      if (cold_timeout_id != 0) {
        Source.remove (cold_timeout_id);
        cold_timeout_id = 0;
      }
    }

    private void update () {
      if (picker == null || picker.is_closed || picker_cancellable.is_cancelled ()) {
        return;
      }
      picker.busy = source != null;

      var filter = picker.filter;
      if (filter == "") {
        picker.empty_message = _("Type to search files");
        picker.set_items (recent_items ());
        return;
      }
      picker.empty_message = _("No matching files");

      var query = new Opus.FuzzyFinder.Query (filter);
      var items = matching_recent_items (query);
      var index = current ?? staging;
      if (index != null) {
        var matches = index.search (query, MAX_RESULTS, picker_cancellable);
        if (matches == null) {
          return;
        }
        bool first = true;
        foreach (var match in matches) {
          var relative_path = index.text_at (match.candidate_index);
          var absolute_path = Path.build_filename (context.root_path, relative_path);
          if (recent.contains (absolute_path)) {
            continue;
          }
          var item = file_item (absolute_path, relative_path, match.ranges);
          if (first) {
            item.separator_label = _("files");
            first = false;
          }
          items.add (item);
        }
      }
      picker.set_items (items);
    }

    private GenericArray<Item> recent_items () {
      var items = new GenericArray<Item> ();
      foreach (var path in recent.all ()) {
        var item = file_item (path, relative_to_root (path), {});
        if (items.length == 0) {
          item.separator_label = _("recently opened");
        }
        items.add (item);
      }
      return items;
    }

    /** Recent files matching on their name alone — a path separator in the query widens that to the whole relative path, as VS Code's own editor-history tier does. */
    private GenericArray<Item> matching_recent_items (Opus.FuzzyFinder.Query query) {
      var scored = new GenericArray<Item> ();
      var scores = new HashTable<Item, int> (direct_hash, direct_equal);
      foreach (var path in recent.all ()) {
        var relative_path = relative_to_root (path);
        var target = query.contains_separator ? relative_path : Path.get_basename (relative_path);
        int score;
        int[] ranges;
        if (!Opus.FuzzyFinder.Scorer.score (target, target.casefold (), query, out score, out ranges)) {
          continue;
        }
        if (!query.contains_separator) {
          ranges = shift_ranges (ranges, relative_path.char_count () - target.char_count ());
        }
        var item = file_item (path, relative_path, ranges);
        scores[item] = score;
        scored.add (item);
      }
      scored.sort_with_data ((a, b) => scores[b] - scores[a]);
      if (scored.length > 0) {
        scored[0].separator_label = _("recently opened");
      }
      return scored;
    }

    private Item file_item (string absolute_path, string relative_path, int[] ranges) {
      var label = Path.get_basename (relative_path);
      var item = new Item (absolute_path, label);
      item.icon_name = label;
      int label_start = relative_path.char_count () - label.char_count ();
      if (label_start > 0) {
        item.description = relative_path.substring (0, relative_path.index_of_nth_char (label_start - 1));
      }
      split_ranges (ranges, label_start, out item.description_highlights, out item.label_highlights);
      return item;
    }

    /** Splits [start, end) ranges over "dir/label" into the two texts' own offsets; the "/" itself belongs to neither. */
    private static void split_ranges (int[] ranges, int label_start, out int[] description_ranges, out int[] label_ranges) {
      int[] in_description = {};
      int[] in_label = {};
      int separator = label_start - 1;
      for (int i = 0; i + 1 < ranges.length; i += 2) {
        int start = ranges[i];
        int end = ranges[i + 1];
        if (label_start > 0 && start < separator) {
          in_description += start;
          in_description += int.min (end, separator);
        }
        if (end > label_start) {
          in_label += int.max (start, label_start) - label_start;
          in_label += end - label_start;
        }
      }
      description_ranges = in_description;
      label_ranges = in_label;
    }

    private static int[] shift_ranges (int[] ranges, int offset) {
      var shifted = new int[ranges.length];
      for (int i = 0; i < ranges.length; i++) {
        shifted[i] = ranges[i] + offset;
      }
      return shifted;
    }

    private string relative_to_root (string path) {
      var prefix = context.root_path + "/";
      return path.has_prefix (prefix) ? path.substring (prefix.length) : path;
    }

    private void on_accepted (Item item) {
      recent.push (item.id);
    }

    private void on_picker_closed () {
      detach_picker ();
    }

    private void detach_picker () {
      cancel_cold_update ();
      if (picker == null) {
        return;
      }
      picker.filter_changed.disconnect (on_filter_changed);
      picker.accepted.disconnect (on_accepted);
      picker.closed.disconnect (on_picker_closed);
      picker = null;
      picker_cancellable = null;
    }

    /**
     * One level only: the explorer reports the directory whose own
     * listing changed, and a subdirectory created with contents gets
     * picked up by the next opening's listing. Reads the disk as is, so
     * a gitignored file created in a watched directory shows up here
     * until that next listing replaces the whole list — a few hundred
     * milliseconds after the next Ctrl+P, not worth a `git check-ignore`
     * round-trip per explorer event.
     */
    private void on_directory_changed (string directory_path) {
      if (current == null) {
        return; // no finished list to patch — the listing in progress reads the disk as it is now
      }
      var relative = relative_to_root (directory_path);
      var directory = relative == directory_path || relative == "" ? "" : relative + "/";

      Dir dir;
      try {
        dir = Dir.open (directory_path);
      } catch (Error e) {
        current.replace_direct_children (directory, {});
        return;
      }
      string[] files = {};
      string? name;
      while ((name = dir.read_name ()) != null) {
        var entry_path = Path.build_filename (directory_path, name);
        if (FileUtils.test (entry_path, FileTest.IS_REGULAR) && !FileUtils.test (entry_path, FileTest.IS_SYMLINK)) {
          files += directory + name;
        }
      }
      current.replace_direct_children (directory, files);
      if (picker != null) {
        update ();
      }
    }
  }
}
