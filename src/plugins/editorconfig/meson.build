# config-file.vala/hierarchy.vala/provider.vala are plain Model-grade
# code (no Peas) — only plugin.vala touches Peas, so
# opus_editorconfig_plugin_sources stays split from it for the tests.
opus_editorconfig_plugin_sources = files(
  'config-file.vala',
  'hierarchy.vala',
  'provider.vala',
  'commands.vala',
)
opus_plugin_sources += opus_editorconfig_plugin_sources + files('plugin.vala')

foreach name : ['config-file', 'hierarchy', 'provider', 'commands']
  editorconfig_test = executable(
    'editorconfig-' + name + '-test',
    ['test' / name + '-test.vala', opus_editorconfig_plugin_sources],
    dependencies: [opus_model_test_dep],
  )
  test('editorconfig-' + name, editorconfig_test)
endforeach
