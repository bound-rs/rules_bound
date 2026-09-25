"""Public API of rules_bound.

For BUILD files:

* `bound_binary`: an executable target as one self-contained executable.

For rules (see the README):

* `BoundInfo`: how a program is laid out in a bundle and started. Rules
  return it to lay out their programs the way their language expects.
* `bound_layout`: the entries of a layout (`files`, `file`, `symlink`,
  `symlinks`, `directory`, `runfiles`).
* `bound_context(ctx)`: builds bound executables in a rule (the ctx
  adaptor); such rules declare `toolchains = [BOUND_TOOLCHAIN_TYPE]`.
* `runfiles_bound_info(executable)`: the BoundInfo of Bazel's own layout, a
  program and its runfiles tree.
* Values for arguments and variables: `RUNTIME_ARGS`, `bundle_path`,
  `runfile`, `raw`; and `rlocation(file)`, a file's runfiles path.
"""

load("//bound/private:binary.bzl", _bound_binary = "bound_binary")
load("//bound/private:context.bzl", _TOOLCHAIN_TYPE = "TOOLCHAIN_TYPE", _bound_context = "bound_context")
load(
    "//bound/private:layout.bzl",
    _BoundInfo = "BoundInfo",
    _RUNTIME_ARGS = "RUNTIME_ARGS",
    _bound_layout = "bound_layout",
    _bundle_path = "bundle_path",
    _raw = "raw",
    _rlocation = "rlocation",
    _runfile = "runfile",
    _runfiles_bound_info = "runfiles_bound_info",
)

bound_binary = _bound_binary
bound_context = _bound_context
BOUND_TOOLCHAIN_TYPE = _TOOLCHAIN_TYPE
BoundInfo = _BoundInfo
bound_layout = _bound_layout
runfiles_bound_info = _runfiles_bound_info
RUNTIME_ARGS = _RUNTIME_ARGS
bundle_path = _bundle_path
runfile = _runfile
raw = _raw
rlocation = _rlocation
