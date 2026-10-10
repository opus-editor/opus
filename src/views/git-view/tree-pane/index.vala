/**
 * The Git activity's main content: the repository's history as a graph,
 * `Branch / Tag | Graph | Commit message`, one Gtk.ColumnView over
 * GitTree rows (each column its own factory and cell class). The
 * working tree, when anything differs, is the top row (GitTree.WorkingRow),
 * in HEAD's lane color at 75%, hanging off its lane. Built once by MainWindow, like
 * StagingPane; set_root_path() swaps the folder, close() runs with the
 * window's destroy.
 *
 * Live: refresh() on the linked WorkspaceContext's own change signals,
 * debounced the way StagingPane debounces, and on StagingPane's
 * repository_changed (a commit touches only `.git`, which the watcher
 * never looks at). A refresh keeps every TreePaneItem whose commit is
 * still there, so the selection stays on it, and tells it `changed`
 * so its cells redraw with the new data. Paged: PAGE_SIZE commits at
 * a time, the next page fetched as the scroll nears the bottom and laid
 * out from the lanes the last row left open (GitTree.Graph.layout's
 * open_lanes), so lines run on across the seam.
 */
namespace GitView {
  public class TreePane : Object {
    private const int PAGE_SIZE = 500;
    // Same constants, same reasoning as StagingPane's own.
    private const uint REFRESH_LATENCY_MS = 400;
    private const int64 COOLDOWN_FACTOR = 10;
    private const int64 MAX_COOLDOWN_US = 5 * TimeSpan.SECOND;
    /** How close to the bottom (in rows) the scroll gets before the next page is asked for. */
    private const int LOAD_MORE_MARGIN_ROWS = 30;

    private Gtk.Box root_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
    private Gtk.ScrolledWindow scrolled = new Gtk.ScrolledWindow () { vexpand = true, hexpand = true };
    private Gtk.ColumnView column_view;
    private Gtk.ColumnViewColumn graph_column;
    private ListStore store = new ListStore (typeof (TreePaneItem));
    private Gtk.SingleSelection selection;
    private TreePanePalette palette = new TreePanePalette ();
    private string? root_path = null;
    // Same guard as StagingPane.status_generation: a slower, earlier load must not land after a later one.
    private int generation = 0;
    private WorkspaceContext? workspace_context = null;
    private uint pending_refresh_id = 0;
    private int64 next_refresh_allowed_at = 0; // monotonic time, microseconds
    // Paging state: how many commits are shown, where the palette and the open lanes stand after the last row, whether git has more.
    private int loaded_commits = 0;
    private int next_color = 0;
    private GenericArray<GitTree.Lane>? open_lanes = null;
    private bool exhausted = false;
    private bool loading = false;
    private GenericArray<GitTree.Stash> stashes = new GenericArray<GitTree.Stash> ();
    private GitTree.WorkingRow? working = null;
    private bool working_tree_dirty = false;

    public Gtk.Widget widget { get { return root_box; } }

    /** The selected row changed — a commit or stash row, or null for nothing/the WIP row. MainWindow swaps the sidebar on it. */
    public signal void row_selected (GitTree.Row? row);

    public TreePane () {
      selection = new Gtk.SingleSelection (store) { autoselect = false, can_unselect = true };
      selection.notify["selected-item"].connect (() => {
        var item = selection.selected_item as TreePaneItem;
        row_selected (item != null ? item.row : null);
      });
      column_view = new Gtk.ColumnView (selection) { show_row_separators = false, show_column_separators = false };
      column_view.add_css_class ("data-table");
      column_view.add_css_class ("tree-pane");

      var ref_column = new Gtk.ColumnViewColumn (_("Branch / Tag"), factory ((item) => {
        var cell = new TreePaneRefCell ();
        item.child = cell.widget;
        cell.widget.set_data ("cell", cell);
      }, (item) => item.child.get_data<TreePaneRefCell> ("cell").bind ((TreePaneItem) item.item))) { resizable = true, fixed_width = 220 };
      graph_column = new Gtk.ColumnViewColumn (_("Graph"), factory ((item) => {
        var cell = new TreePaneGraphCell (palette);
        item.child = cell;
      }, (item) => ((TreePaneGraphCell) item.child).bind ((TreePaneItem) item.item))) { resizable = false };
      var message_column = new Gtk.ColumnViewColumn (_("Commit Message"), factory ((item) => {
        var cell = new TreePaneMessageCell ();
        item.child = cell.widget;
        cell.widget.set_data ("cell", cell);
      }, (item) => item.child.get_data<TreePaneMessageCell> ("cell").bind ((TreePaneItem) item.item))) { expand = true };
      column_view.append_column (ref_column);
      column_view.append_column (graph_column);
      column_view.append_column (message_column);

      scrolled.child = column_view;
      scrolled.vadjustment.value_changed.connect (maybe_load_more);
      root_box.append (palette.widget);
      root_box.append (scrolled);
      GlobalCss.install_from_resource ("/io/github/opus_editor/Opus/styles/tree-pane.css");
    }

    private delegate void CellSetup (Gtk.ListItem item);
    private delegate void CellBind (Gtk.ListItem item);

    /** `bind` runs on bind and again on the item's own `changed`, for as long as the cell stays bound to it. */
    private static Gtk.SignalListItemFactory factory (owned CellSetup setup, owned CellBind bind) {
      var factory = new Gtk.SignalListItemFactory ();
      factory.setup.connect ((object) => setup ((Gtk.ListItem) object));
      factory.bind.connect ((object) => {
        var list_item = (Gtk.ListItem) object;
        bind (list_item);
        var item = (TreePaneItem) list_item.item;
        ulong handler = item.changed.connect (() => bind (list_item));
        list_item.set_data<ulong> ("changed-handler", handler);
      });
      factory.unbind.connect ((object) => {
        var list_item = (Gtk.ListItem) object;
        ((TreePaneItem) list_item.item).disconnect (list_item.get_data<ulong> ("changed-handler"));
      });
      return factory;
    }

    /** MainWindow.link_folder()/unlink_folder() (null) — reloads the whole graph for the new folder, from the first page. */
    public void set_root_path (string? root_path) {
      this.root_path = root_path;
      loaded_commits = 0;
      refresh ();
    }

    /** Re-reads what is shown (every page loaded so far) — the window calls this when StagingPane changed the repository; the watcher's own signals come through set_workspace_context(). */
    public void refresh () {
      reload.begin ();
    }

    /** Same contract as StagingPane.set_workspace_context(): the linked folder's own context, null once unlinked, with any pending debounced refresh dropped. */
    public void set_workspace_context (WorkspaceContext? context) {
      if (workspace_context != null) {
        workspace_context.directory_changed.disconnect (on_workspace_changed);
        workspace_context.file_content_changed.disconnect (on_workspace_changed);
      }
      workspace_context = context;
      if (workspace_context != null) {
        workspace_context.directory_changed.connect (on_workspace_changed);
        workspace_context.file_content_changed.connect (on_workspace_changed);
      }
      if (pending_refresh_id != 0) {
        Source.remove (pending_refresh_id);
        pending_refresh_id = 0;
      }
    }

    public void close () {
      generation++;
      set_workspace_context (null);
    }

    private void on_workspace_changed (string path) {
      if (pending_refresh_id != 0) {
        return; // already waiting — this change just rides along with it
      }
      var cooldown_left_ms = (next_refresh_allowed_at - get_monotonic_time ()) / 1000;
      var delay_ms = (uint) int64.max (REFRESH_LATENCY_MS, cooldown_left_ms);
      pending_refresh_id = Timeout.add (delay_ms, () => {
        pending_refresh_id = 0;
        refresh ();
        return Source.REMOVE;
      });
    }

    /** Everything shown, read again: as many commits as are loaded (one page at least), the stashes and the working tree. */
    private async void reload () {
      int my_generation = ++generation;
      var path = root_path;
      if (path == null) {
        store.remove_all ();
        return;
      }
      var started_at = get_monotonic_time ();
      int limit = int.max (PAGE_SIZE, loaded_commits);
      var commits = yield GitTree.Log.run_async (path, limit);
      var fresh_stashes = yield GitTree.Log.stashes_async (path);
      var tree = yield GitScope.WorkingTree.run_async (path);
      var finished_at = get_monotonic_time ();
      next_refresh_allowed_at = finished_at + int64.min ((finished_at - started_at) * COOLDOWN_FACTOR, MAX_COOLDOWN_US);
      if (my_generation != generation) {
        return;
      }
      commits = commits ?? new GenericArray<GitTree.Commit> ();
      stashes = fresh_stashes ?? new GenericArray<GitTree.Stash> ();
      loaded_commits = (int) commits.length;
      exhausted = commits.length < limit;
      working_tree_dirty = tree != null && tree.unstaged.length + tree.staged.length + tree.conflicts.length > 0;
      next_color = 0;
      var rows = GitTree.Graph.layout (commits, ref next_color, null, stashes, working_tree_dirty);
      open_lanes = rows.length > 0 ? rows[rows.length - 1].open_lanes : null;
      working = tree != null ? GitTree.WorkingRow.create (tree, rows) : null;
      show (rows, true);
    }

    /** The next PAGE_SIZE commits, laid out from where the last row left the lanes and the palette, appended. */
    private async void load_more () {
      if (loading || exhausted || root_path == null) {
        return;
      }
      loading = true;
      int my_generation = generation;
      var path = root_path;
      var commits = yield GitTree.Log.run_async (path, PAGE_SIZE, loaded_commits);
      loading = false;
      if (my_generation != generation || commits == null) {
        return;
      }
      loaded_commits += (int) commits.length;
      exhausted = commits.length < PAGE_SIZE;
      var rows = GitTree.Graph.layout (commits, ref next_color, open_lanes, stashes, working_tree_dirty);
      if (rows.length == 0) {
        return;
      }
      open_lanes = rows[rows.length - 1].open_lanes;
      show (rows, false);
    }

    /*
     * The debug D-Bus surface (Opus.Dev.DevServer) — what a test reads
     * and does, through the same code paths as the real list.
     */

    /** Every row top to bottom as "<kind>|<lane>|<refs>|<text>|<hash>": kind COMMIT/STASH/WIP, refs comma-joined with "*" on the HEAD branch, hash short ("" for WIP). */
    public string[] describe_rows () {
      string[] out = {};
      uint n = store.get_n_items ();
      for (uint i = 0; i < n; i++) {
        var item = (TreePaneItem) store.get_item (i);
        if (item.working != null) {
          out += "WIP|%d||+%d|".printf (item.working.head_lane, item.working.change_count);
          continue;
        }
        var row = item.row;
        if (row.stash != null) {
          out += "STASH|%d||%s|%s".printf (row.node_lane, row.stash.message, row.commit.short_hash);
          continue;
        }
        string[] refs = {};
        for (uint r = 0; r < row.commit.refs.length; r++) {
          var git_ref = row.commit.refs[r];
          refs += (git_ref.is_head ? "*" : "") + git_ref.name;
        }
        out += "COMMIT|%d|%s|%s|%s".printf (row.node_lane, string.joinv (",", refs), row.commit.subject, row.commit.short_hash);
      }
      return out;
    }

    /** Selects the row of the commit whose hash starts with `hash_prefix`; throws when none is shown. */
    public void select_commit (string hash_prefix) throws Error {
      uint n = store.get_n_items ();
      for (uint i = 0; i < n; i++) {
        var item = (TreePaneItem) store.get_item (i);
        if (item.row != null && item.row.commit.hash.has_prefix (hash_prefix)) {
          selection.selected = i;
          return;
        }
      }
      throw new IOError.NOT_FOUND ("No commit %s in the tree".printf (hash_prefix));
    }

    /** The selected commit's short hash, "" with nothing (or the WIP row) selected. */
    public string selected_hash {
      owned get {
        var item = selection.selected_item as TreePaneItem;
        return item != null && item.row != null ? item.row.commit.short_hash : "";
      }
    }

    public int loaded_commit_count { get { return loaded_commits; } }

    /** Back to no selection — HistoryPane's own close button. */
    public void clear_selection () {
      selection.selected = Gtk.INVALID_LIST_POSITION;
    }

    /** Selects the WIP row; throws when there is none. */
    public void select_working_row () throws Error {
      var first = store.get_item (0) as TreePaneItem;
      if (first == null || first.working == null) {
        throw new IOError.NOT_FOUND ("No WIP row in the tree");
      }
      selection.selected = 0;
    }

    /** What scrolling to the bottom does. */
    public void load_more_now () {
      load_more.begin ();
    }

    private void maybe_load_more () {
      var adjustment = scrolled.vadjustment;
      double margin = LOAD_MORE_MARGIN_ROWS * 30.0;
      if (adjustment.value + adjustment.page_size >= adjustment.upper - margin) {
        load_more.begin ();
      }
    }

    /**
     * Puts `rows` on screen — the whole list when `replace`, or appended
     * after what is there. Either way an item already showing the same
     * commit is kept, with its data swapped, rather than replaced: the
     * SingleSelection follows the item object through the splice, so a
     * selected commit stays selected across a refresh.
     */
    private void show (GenericArray<GitTree.Row> rows, bool replace) {
      var existing = new HashTable<string, TreePaneItem> (str_hash, str_equal);
      uint n = store.get_n_items ();
      for (uint i = 0; i < n; i++) {
        var item = (TreePaneItem) store.get_item (i);
        existing[item.key] = item;
      }

      var items = new GenericArray<TreePaneItem> ();
      if (replace && working != null) {
        var item = existing["working-tree"] ?? new TreePaneItem.working_tree (working);
        item.working = working;
        item.changed ();
        items.add (item);
      }
      for (uint i = 0; i < rows.length; i++) {
        var item = existing[rows[i].commit.hash] ?? new TreePaneItem.commit (rows[i]);
        item.row = rows[i];
        item.changed ();
        items.add (item);
      }

      if (replace) {
        store.splice (0, n, (Object[]) items.data);
      } else {
        store.splice (n, 0, (Object[]) items.data);
      }
      mark_working_path ();
      fit_graph_column ();
    }

    /** Marks which rows the WIP line crosses on its way to HEAD, and HEAD itself — over every row shown, since a new page can be where HEAD turns out to be. */
    private void mark_working_path () {
      uint n = store.get_n_items ();
      int head_index = -1;
      for (uint i = 0; i < n; i++) {
        var item = (TreePaneItem) store.get_item (i);
        if (item.row != null && item.row.commit.is_head) {
          head_index = (int) i;
          break;
        }
      }
      for (uint i = 0; i < n; i++) {
        var item = (TreePaneItem) store.get_item (i);
        if (item.row == null) {
          continue;
        }
        bool into_node = working != null && (int) i == head_index;
        int lane = working != null && head_index > (int) i && lane_is_free (item.row, working.head_lane) ? working.head_lane : -1;
        if (item.working_into_node != into_node || item.working_lane != lane) {
          item.working_into_node = into_node;
          item.working_lane = lane;
          item.changed ();
        }
      }
    }

    private void fit_graph_column () {
      int widest = 1;
      uint n = store.get_n_items ();
      for (uint i = 0; i < n; i++) {
        widest = int.max (widest, ((TreePaneItem) store.get_item (i)).lane_count);
      }
      graph_column.fixed_width = widest * TreePaneGraphCell.LANE_WIDTH + 2 * TreePaneGraphCell.SIDE_PADDING;
    }

    /** Whether the WIP line can run down `lane` across `row` without crossing one of its own lines — a stash's own drop into that lane doesn't count: it joins the WIP line, as the stash hangs off the same HEAD. */
    private static bool lane_is_free (GitTree.Row row, int lane) {
      if (row.node_lane == lane) {
        return false;
      }
      for (uint i = 0; i < row.segments.length; i++) {
        var segment = row.segments[i];
        if (segment.top_lane == lane) {
          return false;
        }
        if (segment.bottom_lane == lane && !(row.stash != null && segment.top_lane == GitTree.Segment.NODE)) {
          return false;
        }
      }
      return true;
    }

  }
}
