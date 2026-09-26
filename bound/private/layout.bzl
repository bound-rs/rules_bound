"""Layouts: what a bound bundle contains, where, and how its program starts.

A layout is a list of entries, each placing files at paths in the bundle.
The entries hold depsets and Files as they are; nothing is flattened while
rules are analyzed. Paths are computed when the action runs, by functions
of the entries that `bind` passes to `Args.map_each`.

Everything here is data, with no ctx: a rule can build a layout and return
it in a BoundInfo without declaring the bound toolchain. Only `bind`
(context.bzl) turns layouts into actions.
"""

# Values of arguments and variables.

# The place of the arguments given at run time (by default, the end).
RUNTIME_ARGS = struct(bound_kind = "runtime_args")

def bundle_path(path):
    """A path in the bundle, as an argument or variable value.

    Args:
      path: a `/`-separated path in the bundle, such as `python/lib`.

    Returns:
      A value for `args`, `env`, `env_prepend` and `env_append`, replaced at
      run time by the absolute path of `path` in the extracted bundle, or the
      `cwd` of `bind`: the bundled directory `path`. Something must be
      bundled there.
    """
    return struct(bound_kind = "bundle_path", path = _check_path(path, "bundle_path"))

def runfile(rlocationpath):
    """A path in the bundled runfiles tree, as an argument or variable value.

    Args:
      rlocationpath: the runfiles path, such as `_main/pkg/data.txt` (what
        `$(rlocationpath)` gives).

    Returns:
      A value for `args` or `env`, replaced at run time by the absolute path
      of that file in the extracted bundle. The layout needs a runfiles tree
      (a BoundInfo `runfiles_dir`).
    """
    return struct(bound_kind = "runfile", path = _check_path(rlocationpath, "runfile"))

def raw(argument):
    """An argument or value in bound's own syntax, passed as it is.

    Args:
      argument: a string that may use bound's directives (`@args`,
        `@bundle:PATH`, `@@TEXT`); see bound's README.

    Returns:
      A value for `args` or `env`.
    """
    return struct(bound_kind = "raw", value = argument)

def rlocation_of_path(short_path):
    """The runfiles path for a File's short_path (or an empty file's name).

    Main repository files live in `_main`, external ones in their
    repository's directory (their short paths start with `../`).

    Args:
      short_path: a File's short_path.

    Returns:
      The path under the runfiles root, such as `_main/pkg/data.txt`.
    """
    if short_path.startswith("../"):
        return short_path[3:]
    return "_main/" + short_path

def rlocation(file):
    """The runfiles path of a file, such as `_main/pkg/data.txt`.

    For a file in a tree artifact expanded by `Args.add_all`, the path
    includes its path in the tree.

    Args:
      file: a File.

    Returns:
      The path of the file under the runfiles root. Its first component is
      the file's repository: `rlocation(f).split("/")[0]`.
    """
    return rlocation_of_path(file.short_path)

# Layout entries.

_UNMATCHED = ["error", "skip", "keep"]

def _check_path(path, what, allow_root = False):
    """Normalizes a bundle path, failing on anything that is not one."""
    if type(path) != "string":
        fail("bound: {}: expected a path string, got {}".format(what, type(path)))
    path = path.rstrip("/")
    if not path:
        if allow_root:
            return ""
        fail("bound: {}: the path is empty".format(what))
    if path.startswith("/"):
        fail("bound: {}: \"{}\" is absolute; bundle paths are relative to the bundle root".format(what, path))
    for part in path.split("/"):
        if part in ("", ".", ".."):
            fail("bound: {}: \"{}\" is not a normalized path in the bundle".format(what, path))
    if "=" in path or "\n" in path:
        fail("bound: {}: \"{}\": bundle paths cannot contain '=' or newlines".format(what, path))
    return path

def _path_set(paths):
    """A dict of runfiles paths, from a string, a list or a depset (flattened)."""
    if paths == None:
        return None
    if type(paths) == "string":
        values = [paths]
    elif type(paths) == "depset":
        values = paths.to_list()
    else:
        values = paths
    return {value.rstrip("/"): True for value in values}

def _as_depset(files, what):
    if type(files) == "depset":
        return files
    if type(files) in ("list", "tuple"):
        return depset(files)
    fail("bound: {}: expected a depset or a list, got {}".format(what, type(files)))

def _files(files, dest = "", strip_prefix = None, unmatched = "error", exclude = None):
    """Places files by their runfiles paths, optionally relative to roots.

    Each file goes to `dest/` followed by its runfiles path (such as
    `_main/pkg/a.py` or `pip_six/site-packages/six.py`), from which the
    longest of the `strip_prefix` directories that contains it is removed.
    Tree artifacts are expanded: each file in them is placed by its own
    path. Files declared with `ctx.actions.declare_symlink` are bundled as
    links, with their targets.

    Args:
      files: a depset or list of Files.
      dest: the directory in the bundle; `""` for the root.
      strip_prefix: None to keep the whole runfiles path, or a string or a
        list or depset of strings: runfiles paths of directories, such as the
        import paths of a PyInfo. A depset is flattened here, so it should be
        small. `""` matches every file.
      unmatched: for a file under none of `strip_prefix`: `"error"` (the
        build fails), `"skip"` (it is left out) or `"keep"` (it is placed by
        its whole runfiles path).
      exclude: runfiles paths of files and directories to leave out, as a
        string, a list or a (small) depset.

    Returns:
      A layout entry.
    """
    if unmatched not in _UNMATCHED:
        fail("bound: files: unmatched must be one of {}, not \"{}\"".format(_UNMATCHED, unmatched))
    return struct(
        bound_layout = "files",
        files = _as_depset(files, "files"),
        dest = _check_path(dest, "files dest", allow_root = True),
        prefixes = _path_set(strip_prefix),
        unmatched = unmatched,
        excluded = _path_set(exclude),
    )

def _file(path, file):
    """Places one file at `path`, or a tree artifact's files under it.

    Args:
      path: the path in the bundle.
      file: a File: a file, a tree artifact, or a symlink declared with
        `ctx.actions.declare_symlink` (bundled as a link).

    Returns:
      A layout entry.
    """
    if type(file) != "File":
        fail("bound: file: expected a File, got {}".format(type(file)))
    return struct(bound_layout = "file", path = _check_path(path, "file"), file = file)

def relative_link(path, target):
    """The target text of a link at `path` that points to `target`.

    Args:
      path: the link's path in the bundle.
      target: the path in the bundle that the link points to.

    Returns:
      `target` relative to the link's directory, such as `../store/pkg`.
    """
    link_dir = path.split("/")[:-1]
    target_parts = target.split("/")
    common = 0
    for i in range(min(len(link_dir), len(target_parts))):
        if link_dir[i] != target_parts[i]:
            break
        common = i + 1
    parts = [".."] * (len(link_dir) - common) + target_parts[common:]
    return "/".join(parts) if parts else "."

def _symlink(path, target):
    """A symbolic link at `path` to `target`, another path in the bundle.

    The link is relative (computed from the two paths), so it works wherever
    the bundle is extracted. What it points to must be in the bundle. Links
    are not supported in bundles for Windows.

    Args:
      path: the link's path in the bundle.
      target: the path in the bundle that it points to.

    Returns:
      A layout entry.
    """
    return struct(
        bound_layout = "symlink",
        path = _check_path(path, "symlink"),
        target = _check_path(target, "symlink target"),
    )

def _symlinks(links, dest = ""):
    """Many symbolic links, like `symlink`, computed when the action runs.

    Args:
      links: a depset or list of `(path, target)` tuples of paths in the
        bundle, both under `dest`. A depset lets rules collect the links of
        their dependencies without flattening them, as rules_js does for the
        links of a node_modules tree.
      dest: the directory in the bundle that `path` and `target` are
        relative to; `""` for the root.

    Returns:
      A layout entry.
    """
    return struct(
        bound_layout = "symlinks",
        links = _as_depset(links, "symlinks"),
        dest = _check_path(dest, "symlinks dest", allow_root = True),
    )

def _directory(path):
    """A directory, empty unless other entries place files in it.

    Args:
      path: the directory's path in the bundle.

    Returns:
      A layout entry.
    """
    return struct(bound_layout = "directory", path = _check_path(path, "directory"))

def _runfiles(dest, runfiles, repo_mapping = None):
    """A Bazel runfiles tree at `dest`, as runfiles libraries expect it.

    Files go to their runfiles paths, with the runfiles' symlinks, root
    symlinks and empty files, and `_repo_mapping` if given.

    Args:
      dest: the tree's path in the bundle, such as `app.runfiles`.
      runfiles: a runfiles object.
      repo_mapping: the repository mapping manifest (a File, from
        `files_to_run.repo_mapping_manifest`), or None.

    Returns:
      A layout entry.
    """
    return struct(
        bound_layout = "runfiles",
        dest = _check_path(dest, "runfiles dest"),
        runfiles = runfiles,
        repo_mapping = repo_mapping,
    )

bound_layout = struct(
    files = _files,
    file = _file,
    symlink = _symlink,
    symlinks = _symlinks,
    directory = _directory,
    runfiles = _runfiles,
)

# How to bind a program.

def check_lists(what, lists):
    """Checks list variables: name -> non-empty list of values, no RUNTIME_ARGS.

    Args:
      what: where the lists come from, for messages.
      lists: the dict to check.

    Returns:
      The dict, with its lists copied.
    """
    checked = {}
    for name, values in lists.items():
        if type(values) != "list":
            fail("bound: {}: the value of {} must be a list of entries".format(what, name))
        if not values:
            fail("bound: {}: {} has no entries".format(what, name))
        for value in values:
            if getattr(value, "bound_kind", None) == "runtime_args":
                fail("bound: {}: RUNTIME_ARGS has no place in a list variable".format(what))
        checked[name] = list(values)
    return checked

def check_names(what, groups):
    """Fails if two of `groups` (lists of variable names) share a name.

    Names compare case-insensitively, as bound compares them.

    Args:
      what: where the names come from, for messages.
      groups: lists of names, each bound one way.
    """
    seen = {}
    for group in groups:
        keys = {name.upper(): name for name in group}
        for key, name in keys.items():
            if key in seen:
                fail("bound: {}: the variable {} is bound more than one way (with env, unset, env_prepend or env_append; names compare case-insensitively)".format(what, name))
        seen.update(keys)

def _bound_info_init(layout, program, args = [], env = {}, unset = [], env_prepend = {}, env_append = {}, runfiles_dir = None):
    for entry in layout:
        if not getattr(entry, "bound_layout", None):
            fail("bound: BoundInfo layout: {} is not a layout entry (use bound_layout.files, .file, .symlink, ...)".format(entry))
    env_prepend = check_lists("BoundInfo env_prepend", env_prepend)
    env_append = check_lists("BoundInfo env_append", env_append)
    lists = {name.upper(): name for name in env_prepend.keys() + env_append.keys()}
    check_names("BoundInfo", [env.keys(), list(unset), lists.values()])
    return {
        "layout": list(layout),
        "program": _check_path(program, "BoundInfo program"),
        "args": list(args),
        "env": dict(env),
        "unset": list(unset),
        "env_prepend": env_prepend,
        "env_append": env_append,
        "runfiles_dir": _check_path(runfiles_dir, "BoundInfo runfiles_dir") if runfiles_dir != None else None,
    }

BoundInfo, _new_bound_info = provider(
    doc = """How to bind a program: what its bundle contains, where, and how it starts.

A rule returns BoundInfo to decide how bound lays out its programs: an
interpreter with the application in its site-packages, a node_modules tree,
a JDK and its jars, instead of Bazel's runfiles tree. `bound_binary` uses the
BoundInfo of its `binary` when it has one, and `bound_context(ctx).bind()`
accepts one as its `executable`. Returning BoundInfo needs no toolchain and
registers no action: rules pay nothing unless something binds them.
""",
    fields = {
        "layout": "A list of entries made with `bound_layout`: what the bundle contains, and where.",
        "program": "The path in the bundle of the program to run.",
        "args": "Arguments that start the program, such as an interpreter's options and the module to run. Strings are literal; `bundle_path()`, `runfile()`, `raw()` and `RUNTIME_ARGS` as for `bind`. The arguments given to `bind` (and `bound_args`) follow them.",
        "env": "A dict of variables to set, with values like `args`.",
        "unset": "A list of variables to remove from what the program inherits.",
        "env_prepend": "A dict of list variables, such as `PATH`, to lists of entries put before the caller's value (joined with the platform's separator), with values like `args` except `RUNTIME_ARGS`. Needs bound 0.2.0 or later.",
        "env_append": "A dict of list variables to lists of entries put after the caller's value, like `env_prepend`.",
        "runfiles_dir": "The path in the bundle of a runfiles tree (a `bound_layout.runfiles` entry), or None. With one, `runfile()` values, File values and `bound_binary`'s `data` go there, and RUNFILES_DIR points to it (unless `runfiles_env = False`).",
    },
    init = _bound_info_init,
)

def runfiles_bound_info(executable, runfiles = None):
    """The BoundInfo of Bazel's own layout: a program and its runfiles.

    The program is placed at its own name and its runfiles tree next to it,
    at `<name>.runfiles`, where runfiles libraries look (with, for Bazel's
    Windows launchers, the script they run from next to them). This is what
    `bind` uses for an executable without a BoundInfo.

    Args:
      executable: a Target (with its runfiles and repository mapping) or a
        File (the program alone).
      runfiles: more runfiles to add to the tree, or None.

    Returns:
      A BoundInfo.
    """
    if type(executable) == "Target":
        files_to_run = executable[DefaultInfo].files_to_run
        program = files_to_run.executable
        if not program:
            fail("bound: {} is not executable and has no BoundInfo".format(executable.label))
        tree_runfiles = executable[DefaultInfo].default_runfiles
        repo_mapping = getattr(files_to_run, "repo_mapping_manifest", None)
    elif type(executable) == "File":
        program = executable
        tree_runfiles = None
        repo_mapping = None
    else:
        fail("bound: expected a Target or a File, got {}".format(type(executable)))
    if runfiles:
        tree_runfiles = tree_runfiles.merge(runfiles) if tree_runfiles else runfiles
    name = program.basename
    tree = name + ".runfiles"
    layout = [_file(name, program)]
    if type(executable) == "Target" and name.endswith(".exe"):
        # Bazel's Windows launchers run a script next to them: `<name>` or
        # `<name>.zip` (py_binary), which the target's outputs include.
        stem = name[:-len(".exe")]
        for output in executable[DefaultInfo].files.to_list():
            if output.dirname == program.dirname and output.basename in (stem, stem + ".zip"):
                layout.append(_file(output.basename, output))
    if tree_runfiles or repo_mapping:
        layout.append(_runfiles(tree, tree_runfiles, repo_mapping))
    else:
        layout.append(_directory(tree))
    return BoundInfo(layout = layout, program = name, runfiles_dir = tree)
