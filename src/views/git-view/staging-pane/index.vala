/**
 * The Git activity's sidebar content: a header (folder name, branch)
 * identical in shape to ExplorerPane's own, then one ChangeTree —
 * Staged, Conflicts and Unstaged (GitScope.WorkingTree's own staged/
 * conflicts/unstaged) as collapsible rows over their changes — and a
 * Commit box sized to itself. A row's double-click (ChangeTree's
 * item_activated) stages or unstages just that row; Enter
 * (selection_activated) acts on the current selection, group by group;
 * a refusal from git surfaces through operation_failed.
 *
 * A right-click (show_context_menu()) acts on the selection, one
 * section at a time: Staged first, then Unstaged, then Conflicts.
 * Conflicts — VS Code's own "Merge Changes" group — is only in the
 * tree while there are any; staging one asks first about files still
 * carrying markers or deleted on one side (stage_conflicts()). While a merge/rebase/cherry-pick/revert is
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
 * The tree's sort order follows UserSettings.changes_sort
 * ("name"/"path"/"status", VS Code's own `scm.defaultViewSortKey`),
 * re-applied live on every settings.json change; each row's status
 * letter (ChangeRow's own decoration_letter) follows the user's real
 * editor.font_family the same way, via apply_decoration_font().
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
    private TextArea commit_message_area;
    private Gtk.Label commit_label;
    private Gtk.Button commit_button;
    private Gtk.Button abort_button;
    private Gtk.ScrolledWindow changes_scrolled;
    private ChangeTree changes = new ChangeTree ();
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
        owned get { return commit_message_area.text; }
        set { commit_message_area.text = value; }
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

    /** Exactly one change got selected, under Unstaged or Staged: its diff, as a preview tab — MainWindow opens it. */
    public signal void open_diff_requested (GitDiff.Request request);

    /** Exactly one change got selected, under Conflicts: the file itself, to resolve by hand — MainWindow opens it. */
    public signal void open_file_requested (string path);

    /** Something here just changed the repository — a stage, discard, resolution, commit or abort went through (or failed after touching it). The history view can't learn of a commit from the file watcher, which never looks inside `.git`, so MainWindow relays this to it. */
    public signal void repository_changed ();

    public StagingPane (UserSettings user_settings) {
      this.user_settings = user_settings;

      var builder = new Gtk.Builder.from_resource ("/io/github/opus_editor/Opus/git-view/staging-pane/index.ui");
      root_box = (Gtk.Box) builder.get_object ("root_box");
      root_label = (Gtk.Label) builder.get_object ("root_label");
      branch_label = (Gtk.Label) builder.get_object ("branch_label");
      changes_scrolled = (Gtk.ScrolledWindow) builder.get_object ("changes_scrolled");
      commit_message_area = new TextArea () { placeholder = _("Commit message") };
      commit_message_area.add_css_class ("mt-150");
      commit_message_area.add_css_class ("ms-150");
      commit_message_area.add_css_class ("me-150");
      root_box.insert_child_after (commit_message_area, changes_scrolled);
      commit_message_area.changed.connect (update_commit_button_sensitivity);
      commit_label = (Gtk.Label) builder.get_object ("commit_label");
      commit_button = (Gtk.Button) builder.get_object ("commit_button");
      commit_button.clicked.connect (() => commit.begin ());
      abort_button = (Gtk.Button) builder.get_object ("abort_button");
      abort_button.clicked.connect (() => confirm_and_abort.begin ());
      changes_scrolled.child = changes.widget;
      changes.context_menu_requested.connect (show_context_menu);
      // A double-click acts on just the row clicked; Enter (with a
      // selection) acts on the whole current selection — see
      // ChangeTree's own doc comment for why those are two signals.
      changes.item_activated.connect (activate_change);
      changes.action_requested.connect (run_action);
      changes.group_action_requested.connect (run_group_action);
      changes.selection_activated.connect (activate_selection);
      changes.selection_changed.connect (open_selected);
      update_branch_ui ();

      changes.set_sort_key (user_settings.changes_sort);
      // Live-reload, same as every other editor.*/window.* setting —
      // MainWindow.on_settings_file_changed() is what actually calls
      // user_settings.reload() when settings.json's own tab is open.
      settings_handler = user_settings.changed.connect (() => {
        changes.set_sort_key (user_settings.changes_sort);
        apply_decoration_font ();
      });
      apply_decoration_font ();

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
        changes.set_changes ("staged", new GenericArray<GitScope.Change> (), "");
        changes.set_changes ("conflicts", new GenericArray<GitScope.Change> (), "");
        changes.set_changes ("unstaged", new GenericArray<GitScope.Change> (), "");
        apply_operation (GitScope.OperationKind.NONE, "");
        update_commit_button_sensitivity ();
        return;
      }

      var started_at = get_monotonic_time ();
      var tree = yield GitScope.WorkingTree.run_async (path);
      var finished_at = get_monotonic_time ();
      next_refresh_allowed_at = finished_at + int64.min ((finished_at - started_at) * COOLDOWN_FACTOR, MAX_COOLDOWN_US);

      if (generation != status_generation) {
        return; // superseded by a later set_root_path() while this was in flight
      }

      changes.set_changes ("staged", tree != null ? tree.staged : new GenericArray<GitScope.Change> (), path);
      changes.set_changes ("conflicts", tree != null ? tree.conflicts : new GenericArray<GitScope.Change> (), path);
      changes.set_changes ("unstaged", tree != null ? tree.unstaged : new GenericArray<GitScope.Change> (), path);
      apply_operation (tree != null ? tree.operation : GitScope.OperationKind.NONE, tree != null ? tree.prepared_message : "");
      update_commit_button_sensitivity ();
    }

    /** A double-click on one change: what its section does with it. */
    private void activate_change (GitScope.Change change, string section) {
      switch (section) {
        case "conflicts": stage_conflicts.begin (single (change)); break;
        case "unstaged": stage.begin (single (change)); break;
        default: unstage.begin (single (change)); break;
      }
    }

    /** A row's own inline button, over that row or the selection it is part of (ChangeTree.action_requested): stage (asking a conflict's questions first), unstage, or discard behind its confirmation. */
    private void run_action (string action, GenericArray<GitScope.Change> targets, string section) {
      switch (action) {
        case "unstage": unstage.begin (targets); break;
        case "discard": confirm_and_discard.begin (targets); break;
        default:
          if (section == "conflicts") {
            stage_conflicts.begin (targets);
          } else {
            stage.begin (targets);
          }
          break;
      }
    }

    /** A group row's own button: the whole section staged or unstaged, or discarded behind its confirmation. */
    private void run_group_action (string action, string section) {
      switch (action) {
        case "stage-all": stage.begin (changes.all_changes (section)); break;
        case "unstage-all": unstage.begin (changes.all_changes (section)); break;
        default: confirm_and_discard.begin (changes.all_changes (section)); break;
      }
    }

    /** Enter: the selection, section by section — each a no-op with nothing selected under it. */
    private void activate_selection () {
      stage_conflicts.begin (changes.selected_changes ("conflicts"));
      stage.begin (changes.selected_changes ("unstaged"));
      unstage.begin (changes.selected_changes ("staged"));
    }

    /** One selected change opens its diff as a preview (the file itself, for a conflict); several, or none, open nothing. */
    private void open_selected () {
      var conflicts = changes.selected_changes ("conflicts");
      var unstaged = changes.selected_changes ("unstaged");
      var staged = changes.selected_changes ("staged");
      if (root_path == null || conflicts.length + unstaged.length + staged.length != 1) {
        return;
      }
      if (conflicts.length == 1) {
        open_file_requested (conflicts[0].path);
      } else if (unstaged.length == 1) {
        open_diff_requested (GitDiff.Request.for_working_change (root_path, unstaged[0], "unstaged"));
      } else {
        open_diff_requested (GitDiff.Request.for_working_change (root_path, staged[0], "staged"));
      }
    }

    /**
     * Tracks the parked operation: on the way in, the commit box gets
     * git's own prepared message unless the user already typed
     * something; on the way out, that text is cleared again only if it
     * is still exactly what was put there — the user's own words are
     * never overwritten in either direction.
     */
    private void apply_operation (GitScope.OperationKind kind, string prepared_message) {
      if (kind != operation) {
        if (kind == GitScope.OperationKind.NONE) {
          if (commit_message_area.text == prefilled_message) {
            commit_message_area.text = "";
          }
          prefilled_message = "";
        } else {
          if (commit_message_area.text == "" || commit_message_area.text == prefilled_message) {
            commit_message_area.text = prepared_message;
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

    /** `git add`s `changes` as they currently are — a double-click (just that row), Enter (the current selection) or the debug surface's stage_all() all funnel through this. A no-op with nothing to stage or no folder linked. */
    private async void stage (GenericArray<GitScope.Change> changes) {
      var path = root_path;
      if (path == null || changes.length == 0) {
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

    /** `changes` dropped back out of the index — same callers, same no-op condition, as stage(). */
    private async void unstage (GenericArray<GitScope.Change> changes) {
      var path = root_path;
      if (path == null || changes.length == 0) {
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
      var message = commit_message_area.text;
      bool plain = operation == GitScope.OperationKind.NONE || operation == GitScope.OperationKind.MERGE;
      try {
        if (plain) {
          yield GitScope.Operation.commit_async (path, message);
        } else {
          yield GitScope.Operation.resume_async (path, operation, message);
        }
        commit_message_area.text = "";
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

    /** The right-click menu, for the selection's highest-priority section — Staged, then Unstaged, then Conflicts — and only its rows. Nothing with no change selected. */
    private void show_context_menu (double x, double y) {
      foreach (var section in new string[] { "staged", "unstaged", "conflicts" }) {
        var selected = changes.selected_changes (section);
        if (selected.length > 0) {
          show_section_menu (section, selected, x, y);
          return;
        }
      }
    }

    private void show_section_menu (string section, GenericArray<GitScope.Change> selected, double x, double y) {
      ContextMenu.popup_at (changes.widget, x, y, (popover, box) => {
        switch (section) {
          case "staged":
            box.append (ContextMenu.item (_("Unstage Changes"), () => unstage.begin (selected), popover));
            break;
          case "unstaged":
            box.append (ContextMenu.item (_("Stage Changes"), () => stage.begin (selected), popover));
            box.append (ContextMenu.item (_("Discard Changes"), () => confirm_and_discard.begin (selected), popover));
            break;
          default:
            // HEAD's side of every conflict, staged (GitScope.Resolve.accept_ours)
            // — only a file with both sides still there has that side to take.
            var text_conflicts = text_conflicts_of (selected);
            box.append (ContextMenu.item (_("Stage Changes"), () => stage_conflicts.begin (selected), popover));
            box.append (ContextMenu.item (_("Revert to HEAD"), () => accept_side.begin (text_conflicts, true), popover, null, text_conflicts.length == selected.length));
            break;
        }
        box.append (ContextMenu.separator ());
        box.append (ContextMenu.item (_("Open in Editor"), () => open_in_editor (selected), popover));
      });
    }

    /** Each selected file in a tab — except one deleted from disk, which has nothing to open. */
    private void open_in_editor (GenericArray<GitScope.Change> selected) {
      for (uint i = 0; i < selected.length; i++) {
        if (selected[i].kind != GitScope.ChangeKind.DELETED) {
          open_file_requested (selected[i].path);
        }
      }
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

    private static GenericArray<GitScope.Change> single (GitScope.Change change) {
      var changes = new GenericArray<GitScope.Change> ();
      changes.add (change);
      return changes;
    }

    /**
     * VS Code's own git.clean/git.cleanAll (extensions/git/src/commands.ts)
     * always confirm first, no matter how many files — same here. The
     * words follow what the discard does, as VS Code's do: files deleted
     * from disk come back (a restore, nothing lost), untracked ones are
     * deleted for good, anything else has its edits thrown away. A
     * no-op with nothing to discard or no folder linked.
     */
    private async void confirm_and_discard (GenericArray<GitScope.Change> changes) {
      var path = root_path;
      if (path == null || changes.length == 0) {
        return;
      }
      var name = Path.get_basename (changes[0].path);
      bool confirmed;
      if (all_of_kind (changes, GitScope.ChangeKind.DELETED)) {
        confirmed = yield Dialogs.confirm (
          widget,
          changes.length == 1 ? _("Restore “%s”?").printf (name) : _("Restore all %d files?").printf (changes.length),
          _("The files come back as they are in the last commit."),
          changes.length == 1 ? _("Restore File") : _("Restore All %d Files").printf (changes.length)
        );
      } else if (all_of_kind (changes, GitScope.ChangeKind.UNTRACKED)) {
        confirmed = yield Dialogs.confirm_destructive (
          widget,
          changes.length == 1 ? _("Delete the untracked file “%s”?").printf (name) : _("Delete the %d untracked files?").printf (changes.length),
          _("This can't be undone. The files will be permanently lost."),
          changes.length == 1 ? _("Delete File") : _("Delete All %d Files").printf (changes.length)
        );
      } else {
        confirmed = yield Dialogs.confirm_destructive (
          widget,
          changes.length == 1 ? _("Discard changes in “%s”?").printf (name) : _("Discard changes in %d files?").printf (changes.length),
          _("This can't be undone. Your changes will be permanently lost."),
          _("Discard Changes")
        );
      }
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

    private static bool all_of_kind (GenericArray<GitScope.Change> changes, GitScope.ChangeKind kind) {
      for (uint i = 0; i < changes.length; i++) {
        if (changes[i].kind != kind) {
          return false;
        }
      }
      return true;
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
      var listed = changes.all_changes (section);
      for (uint i = 0; i < listed.length; i++) {
        var change = listed[i];
        var code = change.kind.is_conflict () ? change.conflict_code : change.kind.code ();
        rows += "%s %s".printf (code, change.path.substring (root_path.length + 1));
      }
      return rows;
    }

    public void stage_all () {
      stage.begin (changes.all_changes ("unstaged"));
    }

    public void unstage_all () {
      unstage.begin (changes.all_changes ("staged"));
    }

    public void discard_all () {
      confirm_and_discard.begin (changes.all_changes ("unstaged"));
    }

    /** A double-click on `path`'s row in `section`. */
    public void activate_row (string section, string path) throws Error {
      activate_change (find_change (section, path), section);
    }

    public void accept_current (string path) throws Error {
      accept_side.begin (single (find_change ("conflicts", path)), true);
    }

    public void accept_incoming (string path) throws Error {
      accept_side.begin (single (find_change ("conflicts", path)), false);
    }

    /** Every conflicted file opened in the editor, to resolve block by block. */
    public void solve_all () {
      var conflicts = changes.all_changes ("conflicts");
      for (uint i = 0; i < conflicts.length; i++) {
        open_file_requested (conflicts[i].path);
      }
    }

    /** A single click on `path`'s row in `section` — selects it alone, which opens its diff (or the file, for a conflict). */
    public void select_row (string section, string path) throws Error {
      if (!changes.select_path (section, Path.build_filename (root_path, path))) {
        throw new IOError.NOT_FOUND ("No “%s” row in %s".printf (path, section));
      }
    }

    public void request_commit () {
      commit.begin ();
    }

    public void request_abort () {
      confirm_and_abort.begin ();
    }

    private GitScope.Change find_change (string section, string path) throws Error {
      var listed = changes.all_changes (section);
      for (uint i = 0; i < listed.length; i++) {
        if (listed[i].path == Path.build_filename (root_path, path)) {
          return listed[i];
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

    /** commit_button stays insensitive until "ready to commit" holds in full: a message actually typed, no conflict left (git would refuse that commit anyway), and something staged — except for a merge, whose commit git accepts with the index equal to HEAD (every conflict taken as "ours" leaves exactly that). Called on every buffer change and every refresh_working_tree(). */
    private void update_commit_button_sensitivity () {
      bool needs_staged = operation != GitScope.OperationKind.MERGE;
      commit_button.sensitive = commit_message_area.text != ""
        && !changes.has_items ("conflicts")
        && (changes.has_items ("staged") || !needs_staged);
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
