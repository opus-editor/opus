// The gtk4 vapi types Gtk.TreeListModel's constructor create_func as taking
// a GLib.Object item, but the real C typedef takes an untyped gpointer —
// generating a GCC incompatible-pointer-types warning on every build. This
// raw binding matches the actual C signature exactly, sidestepping the vapi
// entirely instead of living with the warning. Shared by every tree list
// (ExplorerPaneTree, GitView.ChangeTree).
[CCode (cname = "GtkTreeListModelCreateModelFunc", has_target = false)]
public delegate GLib.ListModel? RawCreateModelFunc (void* item, void* user_data);

[CCode (cname = "gtk_tree_list_model_new")]
public extern Gtk.TreeListModel tree_list_model_new_raw (
  owned GLib.ListModel root, bool passthrough, bool autoexpand,
  RawCreateModelFunc create_func, void* user_data, GLib.DestroyNotify? user_destroy
);
