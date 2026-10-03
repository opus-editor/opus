/**
 * What the build baked in. `VERSION` is meson.build's own `version:`,
 * handed to the C compiler as -DOPUS_VERSION (see the root meson.build)
 * — so `opus --version`, the About dialog and the metainfo's release
 * list (bumped together by `just release`) can never disagree.
 */
namespace BuildInfo {
  [CCode (cname = "OPUS_VERSION")]
  public extern const string VERSION;
}
