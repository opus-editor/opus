# Upstream ships Make/CMake only. lib.c is its own amalgamation of the
# whole runtime, so one translation unit is the entire library.
project(
  'tree-sitter', 'c',
  version: '0.27.0',
  default_options: ['warning_level=0', 'c_std=c11'],
)

tree_sitter_include = include_directories('lib/include')

tree_sitter_lib = static_library(
  'tree-sitter',
  'lib/src/lib.c',
  include_directories: [tree_sitter_include, include_directories('lib/src')],
  # The feature macros upstream's own Makefile builds with.
  c_args: ['-D_POSIX_C_SOURCE=200112L', '-D_DEFAULT_SOURCE'],
)

tree_sitter_dep = declare_dependency(
  link_with: tree_sitter_lib,
  include_directories: tree_sitter_include,
)
