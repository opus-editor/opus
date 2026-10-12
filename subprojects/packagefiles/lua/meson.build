# Upstream ships a Makefile only. The interpreter's own sources, every
# file but the two command-line programs (lua.c, luac.c) and the
# single-file amalgamation (onelua.c), as one static library.
project(
  'lua', 'c',
  version: '5.4.7',
  default_options: ['warning_level=0', 'c_std=gnu99'],
)

lua_sources = files(
  'lapi.c', 'lauxlib.c', 'lbaselib.c', 'lcode.c', 'lcorolib.c', 'lctype.c',
  'ldblib.c', 'ldebug.c', 'ldo.c', 'ldump.c', 'lfunc.c', 'lgc.c', 'linit.c',
  'liolib.c', 'llex.c', 'lmathlib.c', 'lmem.c', 'loadlib.c', 'lobject.c',
  'lopcodes.c', 'loslib.c', 'lparser.c', 'lstate.c', 'lstring.c', 'lstrlib.c',
  'ltable.c', 'ltablib.c', 'ltm.c', 'lundump.c', 'lutf8lib.c', 'lvm.c', 'lzio.c',
)

lua_lib = static_library(
  'lua',
  lua_sources,
  c_args: ['-DLUA_USE_LINUX'],
  dependencies: meson.get_compiler('c').find_library('m', required: false),
)

lua_dep = declare_dependency(
  link_with: lua_lib,
  include_directories: include_directories('.'),
)
