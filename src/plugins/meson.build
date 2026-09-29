# Aggregates every plugin's own sources into one list src/meson.build
# appends to opus_sources — each plugin owns its own meson.build/test
# targets; this file only threads opus_plugin_sources through subdir()
# call order (meson shares variable scope across subdir()s, same idiom
# src/meson.build's own opus_model_sources already relies on).
opus_plugin_sources = []
subdir('git-status')
