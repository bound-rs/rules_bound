"""The ctx adaptor: builds bound executables from a rule implementation.

`bind` turns a BoundInfo (a layout and an invocation) into one action that
runs `bound build`. The layout becomes an `--include-list` file of
`DEST=SOURCE` lines, written by functions that `Args.map_each` calls when the
action runs, so that depsets are never flattened during analysis.
"""

load(
    ":layout.bzl",
    "BoundInfo",
    "RUNTIME_ARGS",
    "bound_layout",
    "bundle_path",
    "check_lists",
    "check_names",
    "raw",
    "relative_link",
    "rlocation",
    "rlocation_of_path",
    "runfile",
    "runfiles_bound_info",
)

TOOLCHAIN_TYPE = Label("//bound:toolchain_type")

def _join(dest, path):
    return dest + "/" + path if dest else path

def _line(dest, file):
    """The `DEST=SOURCE` line that bundles `file` at `dest`."""
    if "=" in dest or "\n" in dest:
        fail("bound: cannot bundle {} at \"{}\": bundle paths cannot contain '=' or newlines".format(file.path, dest))
    if file.is_symlink:
        # Declared with ctx.actions.declare_symlink: its target is relative
        # to its place in the bundle, not in the execution root.
        return "{}=@readlink:{}".format(dest, file.path)
    path = file.path
    return "{}={}{}".format(dest, "@" if path.startswith("@") else "", path)

def _is_excluded(path, excluded):
    """Whether `path` or one of its directories is in `excluded`."""
    if path in excluded:
        return True
    end = len(path)
    for _ in range(len(path)):
        end = path.rfind("/", 0, end)
        if end < 0:
            return False
        if path[:end] in excluded:
            return True
    return False

def _strip(path, prefixes):
    """`path` relative to the longest of `prefixes` containing it, or None."""
    end = len(path)
    for _ in range(len(path)):
        end = path.rfind("/", 0, end)
        if end < 0:
            break
        if path[:end] in prefixes:
            return path[end + 1:]
    if "" in prefixes:
        return path
    return None

# The functions below return closures for Args.map_each (allow_closure):
# each captures only the few strings it needs. Bazel fingerprints their
# results, so a change of destination changes the action key.

def _files_mapper(dest, prefixes, unmatched, excluded = None):
    def map_file(file):
        path = rlocation(file)
        if excluded and _is_excluded(path, excluded):
            return None
        if prefixes != None:
            relative = _strip(path, prefixes)
            if relative == None:
                if unmatched == "skip":
                    return None
                if unmatched == "error":
                    fail("bound: {} is under none of the strip_prefix directories {} (unmatched = \"skip\" or \"keep\" to accept that)".format(path, sorted(prefixes.keys())))
                relative = path
            path = relative
        return _line(_join(dest, path), file)

    return map_file

def _file_mapper(path, is_directory):
    def map_file(file):
        if is_directory:
            return _line(path + "/" + file.tree_relative_path, file)
        return _line(path, file)

    return map_file

def _links_mapper(dest):
    def map_link(link):
        path, target = link
        path = _join(dest, path)
        return "{}=@link:{}".format(path, relative_link(path, _join(dest, target)))

    return map_link

def _empty_mapper(dest, empty_path):
    def map_empty(name):
        return "{}/{}={}".format(dest, rlocation_of_path(name), empty_path)

    return map_empty

def _add_file(lines, inputs, path, file):
    lines.add_all(
        [file],
        map_each = _file_mapper(path, file.is_directory),
        allow_closure = True,
        expand_directories = True,
    )
    inputs.append(file)

def _add_entries(ctx, output, entries, lines):
    """Adds the lines of layout entries to `lines`; returns their inputs."""
    direct = []
    transitive = []
    empty = None
    for entry in entries:
        kind = getattr(entry, "bound_layout", None)
        if kind == "files":
            lines.add_all(
                entry.files,
                map_each = _files_mapper(entry.dest, entry.prefixes, entry.unmatched, entry.excluded),
                allow_closure = True,
                expand_directories = True,
                uniquify = True,
            )
            transitive.append(entry.files)
        elif kind == "file":
            _add_file(lines, direct, entry.path, entry.file)
        elif kind == "symlink":
            lines.add("{}=@link:{}".format(entry.path, relative_link(entry.path, entry.target)))
        elif kind == "symlinks":
            lines.add_all(entry.links, map_each = _links_mapper(entry.dest), allow_closure = True, uniquify = True)
        elif kind == "directory":
            lines.add(entry.path + "=@dir")
        elif kind == "runfiles":
            dest = entry.dest
            runfiles = entry.runfiles
            if runfiles:
                lines.add_all(
                    runfiles.files,
                    map_each = _files_mapper(dest, None, "error"),
                    allow_closure = True,
                    expand_directories = True,
                    uniquify = True,
                )
                transitive.append(runfiles.files)

                # Few, and their targets are inputs: flattened here.
                for link in runfiles.symlinks.to_list():
                    _add_file(lines, direct, "{}/_main/{}".format(dest, link.path), link.target_file)
                for link in runfiles.root_symlinks.to_list():
                    _add_file(lines, direct, "{}/{}".format(dest, link.path), link.target_file)
                if runfiles.empty_filenames:
                    if not empty:
                        empty = ctx.actions.declare_file(output.basename + ".empty")
                        ctx.actions.write(empty, "")
                        direct.append(empty)
                    lines.add_all(runfiles.empty_filenames, map_each = _empty_mapper(dest, empty.path), allow_closure = True)
            if entry.repo_mapping:
                _add_file(lines, direct, dest + "/_repo_mapping", entry.repo_mapping)
            if not runfiles and not entry.repo_mapping:
                lines.add(dest + "=@dir")
        else:
            fail("bound: {} is not a layout entry (use bound_layout.files, .file, .symlink, ...)".format(entry))
    return depset(direct, transitive = transitive)

def _render(value, runfiles_dir, files, what):
    """Turns an argument or variable value into bound's syntax."""
    if type(value) == "string":
        # A literal: a leading @ is escaped, so that it is not a directive.
        return "@" + value if value.startswith("@") else value
    if type(value) == "File":
        if runfiles_dir == None:
            fail("bound: {}: {} is a File, which goes into the runfiles tree, but this layout has none (use bundle_path() for a path in the bundle)".format(what, value.short_path))
        files.append(value)
        return "@bundle:{}/{}".format(runfiles_dir, rlocation(value))
    kind = getattr(value, "bound_kind", None)
    if kind == "runtime_args":
        return "@args"
    if kind == "bundle_path":
        return "@bundle:" + value.path
    if kind == "runfile":
        if runfiles_dir == None:
            fail("bound: {}: runfile(\"{}\") needs a runfiles tree, but this layout has none (use bundle_path() for a path in the bundle)".format(what, value.path))
        return "@bundle:{}/{}".format(runfiles_dir, value.path)
    if kind == "raw":
        return value.value
    fail("bound: {}: cannot use {} as a value (use a string, a File, bundle_path(), runfile(), raw() or RUNTIME_ARGS)".format(what, value))

def _is_bound_info(value):
    return type(value) not in ("Target", "File") and hasattr(value, "layout") and hasattr(value, "program")

def bound_info_of(executable, runfiles = None):
    """The BoundInfo to bind for an executable.

    Args:
      executable: a Target (its BoundInfo if it has one, otherwise its
        runfiles layout), a File (the program alone), or a BoundInfo.
      runfiles: more runfiles for the runfiles tree, or None.

    Returns:
      A BoundInfo.
    """
    if type(executable) == "Target" and BoundInfo in executable:
        info = executable[BoundInfo]
    elif type(executable) in ("Target", "File"):
        return runfiles_bound_info(executable, runfiles)
    elif _is_bound_info(executable):
        info = executable
    else:
        fail("bound: expected a Target, a File or a BoundInfo, got {}".format(type(executable)))
    if not runfiles:
        return info
    if not info.runfiles_dir:
        fail("bound: the layout of {} has no runfiles tree (BoundInfo.runfiles_dir) for more runfiles, such as those of bound_binary's data".format(info.program))
    return BoundInfo(
        layout = info.layout + [bound_layout.runfiles(info.runfiles_dir, runfiles)],
        program = info.program,
        args = info.args,
        env = info.env,
        unset = info.unset,
        env_prepend = info.env_prepend,
        env_append = info.env_append,
        runfiles_dir = info.runfiles_dir,
    )

def _render_cwd(cwd):
    """The `--cwd` of `bind`'s `cwd`."""
    if type(cwd) == "string" and cwd in ("inherit", "bundle"):
        return cwd
    if getattr(cwd, "bound_kind", None) == "bundle_path":
        return "@bundle:" + cwd.path
    fail("bound: cwd: expected \"inherit\", \"bundle\" or bundle_path(DIR), got {}".format(cwd))

def _bind(
        ctx,
        toolchain,
        executable,
        layout = [],
        runfiles = None,
        output = None,
        args = [],
        env = {},
        unset = [],
        env_prepend = {},
        env_append = {},
        bundle = "shared",
        cwd = "inherit",
        runfiles_env = None,
        mnemonic = "Bound"):
    info = bound_info_of(executable, runfiles)
    rendered_cwd = _render_cwd(cwd)
    env_prepend = check_lists("bind env_prepend", env_prepend)
    env_append = check_lists("bind env_append", env_append)
    runfiles_dir = info.runfiles_dir
    if runfiles_env == None:
        runfiles_env = runfiles_dir != None
    elif runfiles_env and runfiles_dir == None:
        fail("bound: runfiles_env = True, but the layout of {} has no runfiles tree".format(info.program))
    if not output:
        output = ctx.actions.declare_file(ctx.label.name + toolchain.exe_suffix)

    # Values: the BoundInfo's, then the caller's. A caller's binding of a
    # name replaces the BoundInfo's binding of that name, whatever its kind,
    # except that list entries combine: the caller's prepend entries go
    # before the BoundInfo's and its append entries after them. Names
    # compare case-insensitively, as bound compares them.
    files = []
    rendered_args = [_render(value, runfiles_dir, files, "args") for value in info.args + list(args)]
    caller_lists = {name.upper(): name for name in env_prepend.keys() + env_append.keys()}
    check_names("bind", [env.keys(), list(unset), caller_lists.values()])
    replaced = {name.upper(): True for name in env.keys() + list(unset) + caller_lists.values()}
    variables = {name: value for name, value in info.env.items() if name.upper() not in replaced}
    variables.update(env)
    removed = [name for name in info.unset if name.upper() not in replaced]
    for name in unset:
        if name not in removed:
            removed.append(name)
    rendered_env = ["{}={}".format(name, _render(value, runfiles_dir, files, "env")) for name, value in variables.items()]
    lists = {}
    inherited = [(n, v, True) for n, v in info.env_prepend.items()] + [(n, v, False) for n, v in info.env_append.items()]
    for name, values, before in inherited:
        if name.upper() in replaced and name.upper() not in caller_lists:
            continue
        name, prepended, appended = lists.get(name.upper(), (name, [], []))
        lists[name.upper()] = (name, prepended + values, appended) if before else (name, prepended, appended + values)
    for name, values in env_prepend.items():
        name, prepended, appended = lists.get(name.upper(), (name, [], []))
        lists[name.upper()] = (name, values + prepended, appended)
    for name, values in env_append.items():
        name, prepended, appended = lists.get(name.upper(), (name, [], []))
        lists[name.upper()] = (name, prepended, appended + values)
    rendered_lists = []
    for name, prepended, appended in lists.values():
        rendered_lists += [("--env-prepend", "{}={}".format(name, _render(value, runfiles_dir, files, "env_prepend"))) for value in prepended]
        rendered_lists += [("--env-append", "{}={}".format(name, _render(value, runfiles_dir, files, "env_append"))) for value in appended]

    entries = list(info.layout)
    if files:
        entries.append(bound_layout.runfiles(runfiles_dir, ctx.runfiles(files = files)))
    entries += layout

    # What to bundle, one DEST=SOURCE per line: too many for a command line.
    includes = ctx.actions.declare_file(output.basename + ".includes")
    lines = ctx.actions.args()
    lines.set_param_file_format("multiline")
    inputs = _add_entries(ctx, output, entries, lines)
    ctx.actions.write(includes, lines)

    command = ctx.actions.args()
    command.add("build")
    command.add("--quiet")
    command.add("--launcher", toolchain.launcher)
    command.add("-o", output)
    command.add("--include-list", includes)
    command.add("--bundle", bundle)
    command.add("--cwd", rendered_cwd)
    if runfiles_env:
        # The bundled tree, whatever runfiles variables the caller has
        # (such as those of a `bazel run` or `bazel test` around it).
        command.add("--env", "RUNFILES_DIR=@bundle:" + runfiles_dir)
        command.add("--env", "JAVA_RUNFILES=@bundle:" + runfiles_dir)
        command.add("--unset", "RUNFILES_MANIFEST_FILE")
        command.add("--unset", "RUNFILES_MANIFEST_ONLY")
    for binding in rendered_env:
        command.add("--env", binding)
    for name in removed:
        command.add("--unset", name)
    for option, value in rendered_lists:
        command.add(option, value)
    command.add("--")
    command.add("@bundle:" + info.program)
    command.add_all(rendered_args)

    ctx.actions.run(
        executable = toolchain.bound,
        arguments = [command],
        inputs = depset([includes, toolchain.launcher], transitive = [inputs]),
        outputs = [output],
        mnemonic = mnemonic,
        progress_message = "Binding %{output}",
        toolchain = TOOLCHAIN_TYPE,
    )
    return struct(executable = output, program = info.program, runfiles_dir = runfiles_dir)

def bound_context(ctx):
    """The bound helpers for a rule implementation.

    The rule must declare the bound toolchain: `toolchains =
    [BOUND_TOOLCHAIN_TYPE]`.

    Args:
      ctx: the rule context.

    Returns:
      A struct with:

      * `bind(executable, layout = [], runfiles = None, output = None,
        args = [], env = {}, unset = [], env_prepend = {}, env_append = {},
        bundle = "shared", cwd = "inherit", runfiles_env = None,
        mnemonic = "Bound")`: registers the action that
        writes a bound executable and returns a struct with `executable` (the
        File), `program` (the program's path in the bundle) and
        `runfiles_dir` (the runfiles tree's path in the bundle, or None).

        * `executable`: what to bind. A Target: its BoundInfo if it has one,
          otherwise the program and its runfiles, laid out as Bazel does. A
          File: that program alone. A BoundInfo: any layout.
        * `layout`: more layout entries (`bound_layout`).
        * `runfiles`: more runfiles, for the runfiles tree.
        * `output`: the File to write; by default the rule's name, with
          `.exe` for Windows.
        * `args`: arguments after those of the BoundInfo, before those given
          at run time unless `RUNTIME_ARGS` marks their place. Strings are
          literal; `bundle_path(path)` becomes the absolute path of `path` in
          the extracted bundle, and a File or `runfile(rlocationpath)` that
          of a file in the runfiles tree; `raw(text)` is bound's own syntax.
        * `env`: variables to set, with values like `args`; they override
          those of the BoundInfo.
        * `unset`: variables to remove from the inherited environment.
        * `env_prepend`, `env_append`: list variables such as `PATH`, each
          a name and a list of entries (values like `args`, but not
          `RUNTIME_ARGS`) put before or after the caller's value, joined
          with the platform's separator. The BoundInfo's entries of a name
          sit inside the caller's (its prepend entries after the caller's,
          its append entries before). A name the caller binds any other way
          replaces the BoundInfo's binding of it, and one party cannot bind
          a name two ways; names compare case-insensitively. Needs bound
          0.2.0 or later.
        * `bundle`: "shared" (extracted once into the user's cache,
          read-only) or "private" (extracted for every run).
        * `cwd`: "inherit" (the caller's directory), "bundle", or
          `bundle_path(DIR)`: a directory in the bundle, which the layout
          must hold (needs bound 0.2.0 or later).
        * `runfiles_env`: set RUNFILES_DIR and JAVA_RUNFILES to the bundled
          runfiles tree and remove RUNFILES_MANIFEST_FILE and
          RUNFILES_MANIFEST_ONLY. By default, when the layout has a runfiles
          tree.
      * `toolchain`: the resolved bound toolchain (`bound`, `launcher`,
        `exe_suffix`).
      * `layout`, `runtime_args`, `bundle_path`, `runfile`, `raw`,
        `rlocation`: as exported by defs.bzl (`bound_layout`,
        `RUNTIME_ARGS`, ...).
    """
    toolchain = ctx.toolchains[TOOLCHAIN_TYPE]
    if not toolchain:
        fail("no bound toolchain for this platform; see @rules_bound//bound:extensions.bzl")

    def bind(executable, **kwargs):
        return _bind(ctx, toolchain, executable, **kwargs)

    return struct(
        bind = bind,
        toolchain = toolchain,
        layout = bound_layout,
        runtime_args = RUNTIME_ARGS,
        bundle_path = bundle_path,
        runfile = runfile,
        raw = raw,
        rlocation = rlocation,
    )
