/**
 * The libpeas embedded entry point named by git-status.plugin's Embedded=
 * key. A plain exported function, deliberately NOT [ModuleInit] — one
 * [ModuleInit] anywhere in this whole `valac` invocation would switch
 * every class in Opus to g_type_module_register_type (confirmed from
 * valac's own codegen source, see docs/decisions.md), which this single,
 * hand-written registration function avoids entirely.
 */
[CCode (cname = "opus_git_status_register_types")]
public void opus_git_status_register_types (Peas.ObjectModule module) {
  module.register_extension_type (typeof (FileDecoration.IProvider), typeof (Opus.Plugins.GitStatus.Provider));
}
