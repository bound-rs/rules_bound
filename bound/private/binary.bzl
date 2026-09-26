"""bound_binary: an executable and what it needs, as one executable."""

load(":context.bzl", "TOOLCHAIN_TYPE", "bound_context")
load(":layout.bzl", "bundle_path", "raw", "runfile")

_LOCATIONS = ["location", "execpath", "rootpath", "rlocationpath"]

def _expand(ctx, value, targets, attribute):
    """Turns a whole-argument $(location X) into the bundled file's path.

    Other values are bound's syntax (`@args`, `@@TEXT`, `@bundle:PATH`).
    """
    for kind in _LOCATIONS:
        start = "$(" + kind + " "
        if value.startswith(start) and value.endswith(")"):
            label = value[len(start):-1]
            return runfile(ctx.expand_location("$(rlocationpath {})".format(label), targets))
    if "$(" in value:
        fail("{}: \"{}\": $(location), $(rootpath), $(execpath) and $(rlocationpath) must be whole arguments; they become the absolute path of the bundled file".format(attribute, value))
    return raw(value)

def _cwd(value):
    """`bind`'s cwd for the `cwd` attribute."""
    if value in ("inherit", "bundle"):
        return value
    if value.startswith("@bundle:"):
        return bundle_path(value[len("@bundle:"):].rstrip("/"))
    fail("cwd: expected \"inherit\", \"bundle\" or \"@bundle:DIR\", got \"{}\"".format(value))

def _bound_binary_impl(ctx):
    bound = bound_context(ctx)
    targets = [ctx.attr.binary] + ctx.attr.data
    data_runfiles = None
    if ctx.attr.data:
        data_runfiles = ctx.runfiles(files = ctx.files.data).merge_all(
            [target[DefaultInfo].default_runfiles for target in ctx.attr.data],
        )
    result = bound.bind(
        executable = ctx.attr.binary,
        runfiles = data_runfiles,
        args = [_expand(ctx, value, targets, "bound_args") for value in ctx.attr.bound_args],
        env = {key: _expand(ctx, value, targets, "bound_env") for key, value in ctx.attr.bound_env.items()},
        unset = ctx.attr.unset_env,
        env_prepend = {key: [_expand(ctx, value, targets, "bound_env_prepend") for value in values] for key, values in ctx.attr.bound_env_prepend.items()},
        env_append = {key: [_expand(ctx, value, targets, "bound_env_append") for value in values] for key, values in ctx.attr.bound_env_append.items()},
        bundle = ctx.attr.bundle,
        cwd = _cwd(ctx.attr.cwd),
        runfiles_env = None if ctx.attr.runfiles_env else False,
    )
    return [DefaultInfo(executable = result.executable, files = depset([result.executable]))]

bound_binary = rule(
    implementation = _bound_binary_impl,
    doc = """Turns an executable and what it needs into one self-contained executable.

The output runs without a runfiles tree: copy it anywhere, run it from any
directory, use it as a tool. When it runs, bound extracts the bundle (once,
into the user's cache, with `bundle = "shared"`) and starts the program.

If `binary` provides a BoundInfo, the bundle is laid out as it says (an
interpreter with the application in its site-packages, for example).
Otherwise it holds the program and its runfiles tree, and the program starts
with RUNFILES_DIR pointing at it, so runfiles libraries find every file
where they expect it.

```starlark
load("@rules_bound//bound:defs.bzl", "bound_binary")

bound_binary(
    name = "report",
    binary = ":report_bin",          # any executable: py_binary, sh_binary, cc_binary, ...
    data = ["templates/report.html"],
    bound_args = ["--template", "$(rlocationpath templates/report.html)"],
    bound_env = {"MODE": "production"},
)
```
""",
    attrs = {
        "binary": attr.label(
            doc = "The program: a target with a BoundInfo, or any executable target, whose runfiles are bundled with it.",
            mandatory = True,
            cfg = "target",
        ),
        "data": attr.label_list(
            doc = "More files to bundle, in the runfiles tree (for a BoundInfo, its `runfiles_dir`).",
            allow_files = True,
        ),
        "bound_args": attr.string_list(
            doc = "Arguments bound into the executable, placed before the arguments given at run time unless `@args` marks their place. A whole-argument `$(location X)`, `$(rootpath X)`, `$(execpath X)` or `$(rlocationpath X)` becomes the absolute path of the bundled file at run time. Other values use bound's syntax: `@args`, `@bundle:PATH`, and `@@TEXT` for a literal leading `@`.",
        ),
        "bound_env": attr.string_dict(
            doc = "Environment variables set for the program, with values like `bound_args`.",
        ),
        "unset_env": attr.string_list(
            doc = "Environment variables removed from what the program inherits.",
        ),
        "bound_env_prepend": attr.string_list_dict(
            doc = "List variables, such as PATH, with entries put before the caller's value (joined with the platform's separator, `:` or `;`), with values like `bound_args`. Needs bound 0.2.0 or later.",
        ),
        "bound_env_append": attr.string_list_dict(
            doc = "List variables with entries put after the caller's value, like `bound_env_prepend`.",
        ),
        "bundle": attr.string(
            doc = "\"shared\": the bundle is extracted once, into the user's cache, read-only (as runfiles are), and reused by every run. \"private\": a new copy for every run, removed afterwards.",
            default = "shared",
            values = ["shared", "private"],
        ),
        "cwd": attr.string(
            doc = "\"inherit\": the program runs in the caller's working directory. \"bundle\": in the bundle directory. \"@bundle:DIR\": in the bundled directory DIR (needs bound 0.2.0 or later).",
            default = "inherit",
        ),
        "runfiles_env": attr.bool(
            doc = "When the bundle has a runfiles tree, point RUNFILES_DIR and JAVA_RUNFILES at it and remove RUNFILES_MANIFEST_FILE and RUNFILES_MANIFEST_ONLY, whatever the caller's environment holds.",
            default = True,
        ),
    },
    executable = True,
    toolchains = [TOOLCHAIN_TYPE],
)
