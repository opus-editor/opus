/**
 * The Git activity's sidebar content: a header (folder name, branch, a
 * "..." menu button) identical in shape to ExplorerPane's own, then
 * Unstaged Changes and Staged Changes — each a real ChangeList, from
 * GitScope.WorkingTree's own unstaged/staged — splitting the remaining
 * space evenly, then a Commit button sized to itself. more_button has
 * no click handler yet; Stage All/Unstage All do
 * (GitScope.Stage.add_async()/unstage_async() over that list's own
 * all_changes(), not selected_changes() — they ignore selection
 * entirely; a refusal from git surfaces through operation_failed),
 * and each stays insensitive without anything in its own list at all
 * (ChangeList.has_items). A row's own double-click
 * (ChangeList's own item_activated) instead acts on just that one row,
 * and Enter with a selection (selection_activated) acts on the current
 * selection — three different scopes, see ChangeList's own doc comment
 * for why double-click/Enter needed splitting into two signals to tell
 * them apart at all.
 *
 * Conflicts (GitScope.WorkingTree.conflicts) get a third list above
 * the other two, shown only while there are any — VS Code's own "Merge
 * Changes" group: no discard, but a "…" menu (Accept all current/
 * incoming), a right-click menu per row by its kind (GitScope.Resolve's
 * actions), and staging per row — a double-click, Enter — that asks
 * first about files still carrying markers or deleted on one side
 * (stage_conflicts()). Its "Solve All" button waits on GitDiffTab (see
 * the Blueprint's own TODO). While a merge/rebase/cherry-pick/revert is
 * parked (WorkingTree.operation) the commit box is prefilled with
 * git's own prepared message, the commit button reads "Merge" or
 * "Continue" (GitScope.Operation.commit()/resume()), and an Abort
 * button appears beside it (apply_operation()).
 *
 * MainWindow constructs this once, up front, rather than tying it to
 * link_folder()/unlink_folder() the way ExplorerPane is: nothing here
 * needs tearing down between folders, only set_root_path()/
 * set_branch_provider() updating what the header and commit button show.
 * Between windows it does — see close().
 *
 * Both lists' own sort order follows UserSettings.changes_sort
 * ("name"/"path"/"status", VS Code's own `scm.defaultViewSortKey`),
 * re-applied live on every settings.json change.
 *
 * Each row's status letter (ChangeRow's own decoration_letter, see its
 * doc comment) follows the user's real editor.font_family too, via
 * apply_decoration_font() — re-applied on the same settings.json change
 * as changes_sort above.
 *
 * Live, not just on-link/on-action: set_workspace_context() (wired by
 * MainWindow the same places as GitBranch.IProvider/set_branch_provider())
 * re-runs refresh_working_tree() on WorkspaceContext's own
 * directory_changed/file_content_changed, debounced the same way
 * Opus.Plugins.GitStatus.Provider debounces its own decoration refresh —
 * same latency/cooldown constants, no scope-narrowing needed here since
 * GitScope.WorkingTree.run() always re-reads the whole repository anyway.
 */
namespace GitView {
  public class StagingPane : Object, ISidebarPane {
    // Same constants, same reasoning as Opus.Plugins.GitStatus.Provider's
    // own: the first change of a burst waits this long for the rest of
    // the burst to ride along, and a refresh that itself took a while
    // (a big repository) earns a proportionally longer cooldown before
    // the next one, capped at 5s.
    private const uint REFRESH_LATENCY_MS = 400;
    private const int64 COOLDOWN_FACTOR = 10;
    private const int64 MAX_COOLDOWN_US = 5 * TimeSpan.SECOND;

    private Gtk.Box root_box;
    private Gtk.Label root_label;
    private Gtk.Label branch_label;
    private Gtk.Button more_button;
    private Gtk.Button stage_more_button;
    private Gtk.Button stage_button;
    private Gtk.Button unstage_button;
    private Gtk.TextView commit_message_view;
    private Gtk.Label commit_message_placeholder;
    private Gtk.Label commit_label;
    private Gtk.Button commit_button;
    private Gtk.Button abort_button;
    private Gtk.Box conflicts_box;
    private Gtk.Button conflicts_more_button;
    private Gtk.ScrolledWindow conflicts_scrolled;
    private Gtk.ScrolledWindow unstaged_scrolled;
    private Gtk.ScrolledWindow staged_scrolled;
    private ChangeList conflicts_list = new ChangeList ();
    private ChangeList unstaged_list = new ChangeList ();
    private ChangeList staged_list = new ChangeList ();
    private GitScope.OperationKind operation = GitScope.OperationKind.NONE;
    // What apply_operation() last put in the commit box itself — so it can tell its own text from the user's.
    private string prefilled_message = "";

    /** What the commit button reads, as plain text — "Commit to main", "Merge", "Continue". */
    public string commit_label_text { get; private set; default = ""; }
    /** The last operation_failed summary, "" until one happens — the debug D-Bus surface's way to see a toast. */
    public string last_failure { get; private set; default = ""; }
    /** The parked operation's git name ("merge", "rebase", …), "none" without one. */
    public string operation_name { owned get { return operation == GitScope.OperationKind.NONE ? "none" : operation.subcommand (); } }
    public bool commit_enabled { get { return commit_button.sensitive; } }
    public string commit_message {
        owned get { return commit_message_view.buffer.text; }
        set { commit_message_view.buffer.text = value; }
    }

    private GitBranch.IProvider? branch_provider = null;
    private WorkspaceContext? workspace_context = null;
    private UserSettings user_settings;
    private string? root_path = null;
    // Bumped on every set_root_path() — guards against a slower, earlier
    // GitScope.WorkingTree.run_async() landing after a later one (or
    // after the folder was unlinked), same idiom as EditorPane.TabFindResults's
    // own search_generation.
    private int status_generation = 0;
    private uint pending_refresh_id = 0;
    private int64 next_refresh_allowed_at = 0; // monotonic time, microseconds
    // The last-installed override for .change-decoration-letter's own
    // font-family — see apply_decoration_font().
    private Gtk.CssProvider? decoration_font_provider = null;
    // The handler on user_settings (app-wide, outlives this pane), for close() to undo.
    private ulong settings_handler;

    /** git refused (or isn't there) for something the user just asked for — `summary` is the one-line verdict, `log` git's own words, null when the summary already is the whole story (no git to run at all). A signal, not a toast of its own: a toast belongs to the window, so MainWindow shows it (and its "View Log"). */
    public signal void operation_failed (string summary, string? log);

    /** Something here just changed the repository — a stage, discard, resolution, commit or abort went through (or failed after touching it). The history view can't learn of a commit from the file watcher, which never looks inside `.git`, so MainWindow relays this to it. */
    public signal void repository_changed ();

    public StagingPane (UserSettings user_settings) {
      this.user_settings = user_settings;

      var builder = new Gtk.Builder.from_resource ("/io/github/opus_editor/Opus/git-view/staging-pane/index.ui");
      root_box = (Gtk.Box) builder.get_object ("root_box");
      root_label = (Gtk.Label) builder.get_object ("root_label");
      branch_label = (Gtk.Label) builder.get_object ("branch_label");
      more_button = (Gtk.Button) builder.get_object ("more_button");
      stage_more_button = (Gtk.Button) builder.get_object ("stage_more_button");
      stage_more_button.clicked.connect (() => show_discard_menu ());
      stage_button = (Gtk.Button) builder.get_object ("stage_button");
      unstage_button = (Gtk.Button) builder.get_object ("unstage_button");
      commit_message_view = (Gtk.TextView) builder.get_object ("commit_message_view");
      commit_message_placeholder = (Gtk.Label) builder.get_object ("commit_message_placeholder");
      commit_message_view.buffer.changed.connect (update_commit_message_placeholder);
      commit_message_view.buffer.changed.connect (update_commit_button_sensitivity);
      commit_label = (Gtk.Label) builder.get_object ("commit_label");
      commit_button = (Gtk.Button) builder.get_object ("commit_button");
      commit_button.clicked.connect (() => commit.begin ());
      abort_button = (Gtk.Button) builder.get_object ("abort_button");
      abort_button.clicked.connect (() => confirm_and_abort.begin ());
      conflicts_box = (Gtk.Box) builder.get_object ("conflicts_box");
      conflicts_more_button = (Gtk.Button) builder.get_object ("conflicts_more_button");
      conflicts_more_button.clicked.connect (() => show_conflicts_menu ());
      conflicts_scrolled = (Gtk.ScrolledWindow) builder.get_object ("conflicts_scrolled");
      conflicts_scrolled.child = conflicts_list.widget;
      conflicts_list.context_menu_requested.connect (show_conflict_row_menu);
      conflicts_list.item_activated.connect ((change) => stage_conflicts.begin (single (change)));
      conflicts_list.selection_activated.connect (() => stage_conflicts.begin (conflicts_list.selected_changes ()));
      unstaged_scrolled = (Gtk.ScrolledWindow) builder.get_object ("unstaged_scrolled");
      unstaged_scrolled.child = unstaged_list.widget;
      staged_scrolled = (Gtk.ScrolledWindow) builder.get_object ("staged_scrolled");
      staged_scrolled.child = staged_list.widget;
      update_branch_ui ();

      conflicts_list.set_sort_key (user_settings.changes_sort);
      unstaged_list.set_sort_key (user_settings.changes_sort);
      staged_list.set_sort_key (user_settings.changes_sort);
      // Live-reload, same as every other editor.*/window.* setting —
      // MainWindow.on_settings_file_changed() is what actually calls
      // user_settings.reload() when settings.json's own tab is open.
      settings_handler = user_settings.changed.connect (() => {
        conflicts_list.set_sort_key (user_settings.changes_sort);
        unstaged_list.set_sort_key (user_settings.changes_sort);
        staged_list.set_sort_key (user_settings.changes_sort);
        apply_decoration_font ();
      });
      apply_decoration_font ();

      // Both buttons start sensitive: false in the Blueprint —
      // update_list_button_sensitivity() (called from refresh_working_tree())
      // keeps that in sync with has_items across every folder switch/refresh.
      stage_button.clicked.connect (() => stage.begin (unstaged_list.all_changes ()));
      unstage_button.clicked.connect (() => unstage.begin (staged_list.all_changes ()));
      // A double-click acts on just the row clicked; Enter (with a
      // selection) acts on the whole current selection — see
      // ChangeList's own doc comment for why those are two signals.
      unstaged_list.item_activated.connect ((change) => stage.begin (single (change)));
      staged_list.item_activated.connect ((change) => unstage.begin (single (change)));
      unstaged_list.selection_activated.connect (() => stage.begin (unstaged_list.selected_changes ()));
      staged_list.selection_activated.connect (() => unstage.begin (staged_list.selected_changes ()));

      GlobalCss.install_from_resource ("/io/github/opus_editor/Opus/styles/staging-pane.css");
    }

    public Gtk.Widget widget { get { return root_box; } }

    /**
     * Takes this pane out of the app for good — MainWindow's own destroy
     * handler, same reason ExplorerPane.close() exists: the settings
     * closure above holds `this`, and user_settings is app-wide, so
     * without this a closed window's pane would live on, re-sorting
     * lists nobody sees and reinstalling its font override display-wide
     * on every settings.json reload. Only this instance's own
     * connections and provider go; another window's pane keeps its own.
     */
    public void close () {
      user_settings.disconnect (settings_handler);
      set_branch_provider (null);
      set_workspace_context (null);
      status_generation++; // a refresh still in flight lands on nothing
      if (decoration_font_provider != null) {
        GlobalCss.uninstall (decoration_font_provider);
        decoration_font_provider = null;
      }
    }

    /** MainWindow.link_folder()/unlink_folder() (null) — same text ExplorerPane's own root_label would show, and refreshes the Unstaged/Staged Changes lists for the new folder. */
    public void set_root_path (string? root_path) {
      this.root_path = root_path;
      root_label.label = root_path != null ? Path.get_basename (root_path) : "";
      refresh_working_tree.begin ();
    }

    private async void refresh_working_tree () {
      int generation = ++status_generation;
      var path = root_path;
      if (path == null) {
        conflicts_list.set_changes (new GenericArray<GitScope.Change> (), "");
        unstaged_list.set_changes (new GenericArray<GitScope.Change> (), "");
        staged_list.set_changes (new GenericArray<GitScope.Change> (), "");
        conflicts_box.visible = false;
        apply_operation (GitScope.OperationKind.NONE, "");
        update_commit_button_sensitivity ();
        update_list_button_sensitivity ();
        return;
      }

      var started_at = get_monotonic_time ();
      var tree = yield GitScope.WorkingTree.run_async (path);
      var finished_at = get_monotonic_time ();
      next_refresh_allowed_at = finished_at + int64.min ((finished_at - started_at) * COOLDOWN_FACTOR, MAX_COOLDOWN_US);

      if (generation != status_generation) {
        return; // superseded by a later set_root_path() while this was in flight
      }

      conflicts_list.set_changes (tree != null ? tree.conflicts : new GenericArray<GitScope.Change> (), path);
      unstaged_list.set_changes (tree != null ? tree.unstaged : new GenericArray<GitScope.Change> (), path);
      staged_list.set_changes (tree != null ? tree.staged : new GenericArray<GitScope.Change> (), path);
      conflicts_box.visible = conflicts_list.has_items;
      apply_operation (tree != null ? tree.operation : GitScope.OperationKind.NONE, tree != null ? tree.prepared_message : "");
      update_commit_button_sensitivity ();
      update_list_button_sensitivity ();
    }

    /**
     * Tracks the parked operation: on the way in, the commit box gets
     * git's own prepared message unless the user already typed
     * something; on the way out, that text is cleared again only if it
     * is still exactly what was put there — the user's own words are
     * never overwritten in either direction.
     */
    private void apply_operation (GitScope.OperationKind kind, string prepared_message) {
      var buffer = commit_message_view.buffer;
      if (kind != operation) {
        if (kind == GitScope.OperationKind.NONE) {
          if (buffer.text == prefilled_message) {
            buffer.text = "";
          }
          prefilled_message = "";
        } else {
          if (buffer.text == "" || buffer.text == prefilled_message) {
            buffer.text = prepared_message;
          }
          prefilled_message = prepared_message;
        }
        operation = kind;
      }
      abort_button.visible = operation != GitScope.OperationKind.NONE;
      update_branch_ui ();
    }

    /**
     * Wires live refreshing to the linked folder's own WorkspaceContext
     * (null once unlinked) — MainWindow calls this the same places it
     * calls set_branch_provider(). Drops any refresh still waiting on
     * the old context first: a change debounced right before a folder
     * switch has nothing left to refresh once its context is gone.
     */
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

    private void on_workspace_changed (string path) {
      if (pending_refresh_id != 0) {
        return; // already waiting — this change just rides along with it
      }
      var cooldown_left_ms = (next_refresh_allowed_at - get_monotonic_time ()) / 1000;
      var delay_ms = (uint) int64.max (REFRESH_LATENCY_MS, cooldown_left_ms);
      pending_refresh_id = Timeout.add (delay_ms, () => {
        pending_refresh_id = 0;
        refresh_working_tree.begin ();
        return Source.REMOVE;
      });
    }

    /** `git add`s `changes` as they currently are — Stage All (every row), a double-click (just that row), or Enter (the current selection) all funnel through this. A no-op with no folder linked. */
    private async void stage (GenericArray<GitScope.Change> changes) {
      var path = root_path;
      if (path == null) {
        return;
      }
      try {
        yield GitScope.Stage.add_async (path, paths_of (changes));
      } catch (GitScope.CommandError e) {
        report_failure (_("Couldn’t stage the changes"), e);
      }
      yield refresh_working_tree ();
      repository_changed ();
    }

    /** `changes` dropped back out of the index — same three callers, same no-op condition, as stage(). */
    private async void unstage (GenericArray<GitScope.Change> changes) {
      var path = root_path;
      if (path == null) {
        return;
      }
      try {
        yield GitScope.Stage.unstage_async (path, paths_of (changes));
      } catch (GitScope.CommandError e) {
        report_failure (_("Couldn’t unstage the changes"), e);
      }
      yield refresh_working_tree ();
      repository_changed ();
    }

    /** The commit button: a plain commit (the merge commit too — git closes a parked merge by itself), or the parked rebase/cherry-pick/revert's own `--continue` with the box's text as the stopped commit's message. */
    private async void commit () {
      var path = root_path;
      if (path == null) {
        return;
      }
      var message = commit_message_view.buffer.text;
      bool plain = operation == GitScope.OperationKind.NONE || operation == GitScope.OperationKind.MERGE;
      try {
        if (plain) {
          yield GitScope.Operation.commit_async (path, message);
        } else {
          yield GitScope.Operation.resume_async (path, operation, message);
        }
        commit_message_view.buffer.text = "";
        prefilled_message = "";
      } catch (GitScope.CommandError e) {
        report_failure (plain ? _("Couldn’t commit the changes") : _("Couldn’t continue the %s").printf (operation.subcommand ()), e);
      }
      yield refresh_working_tree ();
      repository_changed ();
    }

    private async void confirm_and_abort () {
      var path = root_path;
      var kind = operation;
      if (path == null || kind == GitScope.OperationKind.NONE) {
        return;
      }
      var confirmed = yield Dialogs.confirm_destructive (
        widget,
        _("Abort the %s?").printf (kind.subcommand ()),
        _("Everything resolved so far will be lost, and the repository goes back to how it was before it started."),
        _("Abort")
      );
      if (!confirmed) {
        return;
      }
      try {
        yield GitScope.Operation.abort_async (path, kind);
      } catch (GitScope.CommandError e) {
        report_failure (_("Couldn’t abort the %s").printf (kind.subcommand ()), e);
      }
      yield refresh_working_tree ();
      repository_changed ();
    }

    /** conflicts_more_button's own "…" menu — whole-side resolution for every text conflict at once; files one side deleted have no "side" to take and are left to Stage All's own questions. */
    private void show_conflicts_menu () {
      var text_conflicts = text_conflicts_of (conflicts_list.all_changes ());
      ContextMenu.popup_at (conflicts_more_button, 0, conflicts_more_button.get_height (), (popover, box) => {
        box.append (ContextMenu.item (_("Accept all current"), () => accept_side.begin (text_conflicts, true), popover, null, text_conflicts.length > 0));
        box.append (ContextMenu.item (_("Accept all incoming"), () => accept_side.begin (text_conflicts, false), popover, null, text_conflicts.length > 0));
      });
    }

    /** Right-click on one conflict row: the actions its kind allows, VS Code's own wording. */
    private void show_conflict_row_menu (GitScope.Change? change, double x, double y) {
      if (change == null) {
        return;
      }
      ContextMenu.popup_at (conflicts_list.widget, x, y, (popover, box) => {
        switch (change.kind) {
          case GitScope.ChangeKind.DELETED_BY_THEM:
            box.append (ContextMenu.item (_("Keep Our Version"), () => keep_or_remove.begin (single (change), true), popover));
            box.append (ContextMenu.item (_("Delete File"), () => keep_or_remove.begin (single (change), false), popover));
            break;
          case GitScope.ChangeKind.DELETED_BY_US:
            box.append (ContextMenu.item (_("Keep Their Version"), () => keep_or_remove.begin (single (change), true), popover));
            box.append (ContextMenu.item (_("Delete File"), () => keep_or_remove.begin (single (change), false), popover));
            break;
          default:
            box.append (ContextMenu.item (_("Accept current"), () => accept_side.begin (single (change), true), popover));
            box.append (ContextMenu.item (_("Accept incoming"), () => accept_side.begin (single (change), false), popover));
            break;
        }
      });
    }

    private async void accept_side (GenericArray<GitScope.Change> changes, bool ours) {
      var path = root_path;
      if (path == null || changes.length == 0) {
        return;
      }
      try {
        if (ours) {
          yield GitScope.Resolve.accept_ours_async (path, paths_of (changes));
        } else {
          yield GitScope.Resolve.accept_theirs_async (path, paths_of (changes));
        }
      } catch (GitScope.CommandError e) {
        report_failure (_("Couldn’t resolve the conflicts"), e);
      }
      yield refresh_working_tree ();
      repository_changed ();
    }

    private async void keep_or_remove (GenericArray<GitScope.Change> changes, bool keep) {
      var path = root_path;
      if (path == null || changes.length == 0) {
        return;
      }
      try {
        if (keep) {
          yield GitScope.Resolve.keep_async (path, paths_of (changes));
        } else {
          yield GitScope.Resolve.remove_async (path, paths_of (changes));
        }
      } catch (GitScope.CommandError e) {
        report_failure (_("Couldn’t resolve the conflicts"), e);
      }
      yield refresh_working_tree ();
      repository_changed ();
    }

    /**
     * Staging conflicts (a row's double-click/Enter) — VS Code's own git.stage over merge
     * resources (extensions/git/src/commands.ts): a file one side
     * deleted gets its own keep-or-delete question; a file still
     * carrying conflict markers counts toward one "stage with merge
     * conflicts?" question; a file whose markers are gone is staged
     * without a word. Cancelling any question stages nothing at all.
     */
    private async void stage_conflicts (GenericArray<GitScope.Change> changes) {
      var path = root_path;
      if (path == null || changes.length == 0) {
        return;
      }
      string[] to_keep = {};
      string[] to_remove = {};
      var unresolved = new GenericArray<GitScope.Change> ();
      for (uint i = 0; i < changes.length; i++) {
        var change = changes[i];
        if (change.kind == GitScope.ChangeKind.CONFLICT) {
          if (GitScope.Resolve.has_conflict_markers (change.path)) {
            unresolved.add (change);
          } else {
            to_keep += change.path;
          }
          continue;
        }
        var choice = yield ask_about_deletion (change);
        if (choice < 0) {
          return;
        }
        if (choice == 0) {
          to_keep += change.path;
        } else {
          to_remove += change.path;
        }
      }
      if (unresolved.length > 0) {
        if (!yield confirm_staging_with_markers (unresolved)) {
          return;
        }
        foreach (var change in unresolved.data) {
          to_keep += change.path;
        }
      }
      try {
        yield GitScope.Resolve.keep_async (path, to_keep);
        yield GitScope.Resolve.remove_async (path, to_remove);
      } catch (GitScope.CommandError e) {
        report_failure (_("Couldn’t stage the changes"), e);
      }
      yield refresh_working_tree ();
      repository_changed ();
    }

    /** 0 to keep the file as it is on disk, 1 to delete it, -1 for Cancel. */
    private async int ask_about_deletion (GitScope.Change change) {
      bool by_them = change.kind == GitScope.ChangeKind.DELETED_BY_THEM;
      var body = by_them
        ? _("It was deleted by them and modified by us.")
        : _("It was deleted by us and modified by them.");
      return yield Dialogs.choose (
        widget,
        _("Keep or delete “%s”?").printf (Path.get_basename (change.path)),
        body,
        _("Keep File"),
        _("Delete File"),
        "destructive-action"
      );
    }

    private async bool confirm_staging_with_markers (GenericArray<GitScope.Change> unresolved) {
      var heading = unresolved.length == 1
        ? _("Are you sure you want to stage “%s” with merge conflicts?").printf (Path.get_basename (unresolved[0].path))
        : _("Are you sure you want to stage %u files with merge conflicts?").printf (unresolved.length);
      return yield Dialogs.confirm (widget, heading, _("The conflict markers will be staged as they are."), _("Yes"));
    }

    private static GenericArray<GitScope.Change> text_conflicts_of (GenericArray<GitScope.Change> changes) {
      var result = new GenericArray<GitScope.Change> ();
      for (uint i = 0; i < changes.length; i++) {
        if (changes[i].kind == GitScope.ChangeKind.CONFLICT) {
          result.add (changes[i]);
        }
      }
      return result;
    }

    private static GenericArray<GitScope.Change> single (GitScope.Change change) {
      var changes = new GenericArray<GitScope.Change> ();
      changes.add (change);
      return changes;
    }

    /** stage_more_button's own "…" menu — see its doc comment on the Blueprint side. */
    private void show_discard_menu () {
      ContextMenu.popup_at (stage_more_button, 0, stage_more_button.get_height (), (popover, box) => {
        box.append (ContextMenu.item (_("Discard changes on selected files"), () => confirm_and_discard.begin (unstaged_list.selected_changes ()), popover, null, unstaged_list.has_selection));
        box.append (ContextMenu.item (_("Discard all changes"), () => confirm_and_discard.begin (unstaged_list.all_changes ()), popover, null, unstaged_list.has_items));
      });
    }

    /** VS Code's own git.clean/git.cleanAll (extensions/git/src/commands.ts) always confirm first, no matter how many files — same here, one shared dialog for both the selected-files and the all-files call, same wording either way. A no-op with nothing to discard or no folder linked. */
    private async void confirm_and_discard (GenericArray<GitScope.Change> changes) {
      var path = root_path;
      if (path == null || changes.length == 0) {
        return;
      }
      var heading = changes.length == 1
        ? _("Discard changes in “%s”?").printf (Path.get_basename (changes[0].path))
        : _("Discard changes in %d files?").printf (changes.length);
      var confirmed = yield Dialogs.confirm_destructive (
        widget,
        heading,
        _("This can't be undone. Your changes will be permanently lost."),
        _("Discard Changes")
      );
      if (!confirmed) {
        return;
      }
      try {
        yield GitScope.Discard.run_async (path, changes);
      } catch (GitScope.CommandError e) {
        report_failure (_("Couldn’t discard the changes"), e);
      }
      yield refresh_working_tree ();
      repository_changed ();
    }

    /** NOT_AVAILABLE's own message is already the one line a user needs, so it goes out as the summary itself, with no log behind it. */
    private void report_failure (string summary, GitScope.CommandError e) {
      last_failure = summary;
      Logger.warn ("%s: %s".printf (summary, e.message));
      if (e is GitScope.CommandError.NOT_AVAILABLE) {
        operation_failed (e.message, null);
        return;
      }
      operation_failed (summary, e.message);
    }

    /*
     * The debug D-Bus surface (Opus.Dev.DevServer) — each of these is
     * exactly what a click does, through the same code path, dialogs
     * included (answered through Dialogs.respond()). `section` is
     * "conflicts"/"unstaged"/"staged"; a `path` is relative to the root.
     */

    /** Each row as "<code> <relative path>" in list order — "M src/a.vala", "UU b.txt". */
    public string[] list_changes (string section) {
      string[] rows = {};
      var changes = list_for (section).all_changes ();
      for (uint i = 0; i < changes.length; i++) {
        var change = changes[i];
        var code = change.kind.is_conflict () ? change.conflict_code : change.kind.code ();
        rows += "%s %s".printf (code, change.path.substring (root_path.length + 1));
      }
      return rows;
    }

    public void stage_all () {
      stage.begin (unstaged_list.all_changes ());
    }

    public void unstage_all () {
      unstage.begin (staged_list.all_changes ());
    }

    public void discard_all () {
      confirm_and_discard.begin (unstaged_list.all_changes ());
    }

    /** A double-click on `path`'s row in `section`. */
    public void activate_row (string section, string path) throws Error {
      var change = find_change (section, path);
      switch (section) {
        case "conflicts": stage_conflicts.begin (single (change)); break;
        case "unstaged": stage.begin (single (change)); break;
        default: unstage.begin (single (change)); break;
      }
    }

    public void accept_current (string path) throws Error {
      accept_side.begin (single (find_change ("conflicts", path)), true);
    }

    public void accept_incoming (string path) throws Error {
      accept_side.begin (single (find_change ("conflicts", path)), false);
    }

    public void request_commit () {
      commit.begin ();
    }

    public void request_abort () {
      confirm_and_abort.begin ();
    }

    private ChangeList list_for (string section) {
      switch (section) {
        case "conflicts": return conflicts_list;
        case "unstaged": return unstaged_list;
        default: return staged_list;
      }
    }

    private GitScope.Change find_change (string section, string path) throws Error {
      var changes = list_for (section).all_changes ();
      for (uint i = 0; i < changes.length; i++) {
        if (changes[i].path == Path.build_filename (root_path, path)) {
          return changes[i];
        }
      }
      throw new IOError.NOT_FOUND ("No “%s” row in %s".printf (path, section));
    }

    /** Every path git needs to hear about — a rename's old path included (see GitScope.Change.old_path). */
    private static string[] paths_of (GenericArray<GitScope.Change> changes) {
      string[] paths = {};
      for (uint i = 0; i < changes.length; i++) {
        paths += changes[i].path;
        if (changes[i].old_path != null) {
          paths += changes[i].old_path;
        }
      }
      return paths;
    }

    /**
     * Each ChangeRow's own status-letter label carries the Blueprint's
     * "monospace" class already (resolves fontconfig's own "monospace"
     * alias, same fallback CodeEditor's own font_css() leans on) — this
     * only installs an override when the user actually set
     * editor.font_family, same "omit it otherwise" shape as that
     * method. Uninstalls its own previous override first: a value the
     * last reload set and this one omits (font_family going back to
     * null) needs the old rule gone outright, not just uncontested by
     * a provider that no longer mentions it.
     */
    private void apply_decoration_font () {
      if (decoration_font_provider != null) {
        GlobalCss.uninstall (decoration_font_provider);
        decoration_font_provider = null;
      }
      if (user_settings.font_family == null) {
        return;
      }
      var css = ".change-decoration-letter { font-family: \"%s\"; }\n".printf (user_settings.font_family.replace ("\"", "'"));
      decoration_font_provider = GlobalCss.install_from_string (css);
    }

    /** Whose current_branch() the header and commit button show — same contract as ExplorerPane.set_branch_provider(). */
    public void set_branch_provider (GitBranch.IProvider? provider) {
      if (branch_provider != null) {
        branch_provider.branch_changed.disconnect (update_branch_ui);
      }
      branch_provider = provider;
      if (branch_provider != null) {
        branch_provider.branch_changed.connect (update_branch_ui);
      }
      update_branch_ui ();
    }

    /** Gtk.TextView has no native placeholder-text — commit_message_placeholder is a plain overlaid Gtk.Label, visible only while the buffer is genuinely empty. */
    private void update_commit_message_placeholder () {
      commit_message_placeholder.visible = commit_message_view.buffer.text == "";
    }

    /** commit_button stays insensitive until "ready to commit" holds in full: a message actually typed, no conflict left (git would refuse that commit anyway), and something staged — except for a merge, whose commit git accepts with the index equal to HEAD (every conflict taken as "ours" leaves exactly that). Called on every buffer change and every refresh_working_tree(). */
    private void update_commit_button_sensitivity () {
      bool needs_staged = operation != GitScope.OperationKind.MERGE;
      commit_button.sensitive = commit_message_view.buffer.text != ""
        && !conflicts_list.has_items
        && (staged_list.has_items || !needs_staged);
    }

    /** Stage All/Unstage All stay insensitive with nothing in their own list at all — they act on the whole list, so selection doesn't factor in. */
    private void update_list_button_sensitivity () {
      stage_button.sensitive = unstaged_list.has_items;
      unstage_button.sensitive = staged_list.has_items;
    }

    private void update_branch_ui () {
      string? branch = branch_provider?.current_branch ();
      branch_label.label = branch ?? _("No branch");
      switch (operation) {
        case GitScope.OperationKind.MERGE:
          commit_label_text = _("Merge");
          commit_label.label = commit_label_text;
          break;
        case GitScope.OperationKind.REBASE:
        case GitScope.OperationKind.CHERRY_PICK:
        case GitScope.OperationKind.REVERT:
          commit_label_text = _("Continue");
          commit_label.label = commit_label_text;
          break;
        default:
          commit_label_text = branch != null ? _("Commit to %s").printf (branch) : _("Commit");
          commit_label.label = branch != null
            ? _("Commit to <b>%s</b>").printf (Markup.escape_text (branch))
            : _("Commit");
          break;
      }
    }
  }
}
