/** The libpeas embedded entry point named by editorconfig.plugin's Embedded= key — a plain exported function, not [ModuleInit], for the reason git-status/plugin.vala gives. */
[CCode (cname = "opus_editorconfig_register_types")]
public void opus_editorconfig_register_types (Peas.ObjectModule module) {
  module.register_extension_type (typeof (FileSettings.IProvider), typeof (Opus.Plugins.EditorConfig.Provider));
}
