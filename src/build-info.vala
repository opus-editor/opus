/**
 * What the build baked in. `VERSION` is meson.build's own `version:`,
 * handed to the C compiler as -DOPUS_VERSION (see the root meson.build)
 * — so `opus --version`, the About dialog and the metainfo's release
 * list (bumped together by `just release`) can never disagree.
 */
namespace BuildInfo {
  [CCode (cname = "OPUS_VERSION")]
  public extern const string VERSION;

  /** Where `ninja install` put the bundled language packages. */
  [CCode (cname = "OPUS_LANGUAGES_DIR")]
  public extern const string LANGUAGES_DIR;

  /** Where `ninja install` put the bundled themes. */
  [CCode (cname = "OPUS_THEMES_DIR")]
  public extern const string THEMES_DIR;

  /** Where `ninja install` put their compiled grammars. */
  [CCode (cname = "OPUS_GRAMMARS_DIR")]
  public extern const string GRAMMARS_DIR;
}
