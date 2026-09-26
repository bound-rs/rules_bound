# rules_bound

Bazel rules for [bound](https://github.com/bound-rs/bound): turn an
executable target into **one self-contained executable**, laid out the way
its language expects, with no runfiles tree.

A Bazel binary is rarely one file. A `py_binary` needs its interpreter, its
dependencies and its data; a JavaScript program needs `node` and a
`node_modules` tree; a `sh_binary` needs its runfiles tree. They run inside
`bazel run`, and anywhere else only if their runfiles come along, found by
runfiles libraries or by a language's own runfiles logic (rules_js patches
`require` and the file system for it).

bound writes a single native executable instead: a launcher followed by a
compressed bundle. When it runs, the bundle is extracted (once, into the
user's cache) and the program starts. rules_bound gives two ways to lay out
that bundle:

* **Any executable**, as Bazel lays it out: the program and its runfiles
  tree, with `RUNFILES_DIR` pointing at it. Nothing to write:
  `bound_binary(binary = ":tool")`.
* **As its language expects**: a Python interpreter with the application in
  its own `site-packages`, `node` with a real `node_modules` tree, a JDK
  and its jars. Programs then find their files by the language's own
  rules, as installed programs do, and need no runfiles at all. Rules
  describe such a layout with a `BoundInfo`, made of language-agnostic
  building blocks ([`bound_layout`](#layouts-for-rule-authors)), and
  `bound_binary` uses it.

```starlark
load("@rules_bound//bound:defs.bzl", "bound_binary")

bound_binary(
    name = "report_bound",
    binary = ":report",        # a py_binary, sh_binary, cc_binary, ... or a target with a BoundInfo
)
```

```sh
bazel build //:report_bound
cp bazel-bin/report_bound /usr/local/bin/report    # one file: interpreter, packages, data
report sales.csv
```

## Setup

```starlark
# MODULE.bazel
bazel_dep(name = "rules_bound", version = "0.2.1")
```

rules_bound declares a toolchain of the released `bound` binaries for every
pair of execution and target platform (Linux and Windows on x86_64 and
aarch64, macOS on Apple silicon), downloaded when a build needs it, so a
build on Linux can produce an executable for macOS or Windows, given a
target of that platform to bind. It uses bound 0.2.1 unless your module
chooses another release (list variables and `cwd` in the bundle need 0.2.0
or later; an older bound fails on the unknown option):

```starlark
bound = use_extension("@rules_bound//bound:extensions.bzl", "bound")
bound.toolchain(version = "0.2.1")
```

For a version rules_bound does not know yet, pass the archives' checksums:
`bound.toolchain(version = "…", sha256s = {"linux_x86_64": "…", …})`.

To use binaries you built yourself, for the host platform only:

```starlark
bound.local(path = "../bound/target/release")   # relative to your module, or absolute
```

or declare a toolchain of your own with `bound_toolchain` (see
[bound/toolchain.bzl](bound/toolchain.bzl)).

## `bound_binary`

| Attribute | Meaning |
|---|---|
| `binary` | The program: a target with a `BoundInfo`, laid out as it says, or any executable target, bundled with its runfiles. |
| `data` | More files to bundle, in the runfiles tree (for a `BoundInfo`, its `runfiles_dir`). |
| `bound_args` | Arguments bound into the executable, after those of the `BoundInfo` and before the arguments given at run time unless `@args` marks their place. A whole-argument `$(location X)`, `$(rootpath X)`, `$(execpath X)` or `$(rlocationpath X)` becomes the absolute path of the bundled file at run time (it needs a runfiles tree). Other values use [bound's syntax](https://github.com/bound-rs/bound#reference): `@args`, `@bundle:PATH`, and `@@TEXT` for a literal leading `@`. |
| `bound_env` | Environment variables set for the program, with values like `bound_args`. |
| `unset_env` | Environment variables removed from what the program inherits. |
| `bound_env_prepend` | List variables, such as `PATH`, each with entries put before the caller's value (joined with the platform's separator, `:` or `;`), with values like `bound_args`. |
| `bound_env_append` | List variables with entries put after the caller's value. |
| `bundle` | `"shared"` (default): the bundle is extracted once, into the user's cache, read-only, and reused by every run. `"private"`: a new copy for every run, removed afterwards. |
| `cwd` | `"inherit"` (default): the program runs in the caller's working directory. `"bundle"`: in the bundle directory. `"@bundle:DIR"`: in the bundled directory `DIR`. |
| `runfiles_env` | When the bundle has a runfiles tree, point `RUNFILES_DIR` and `JAVA_RUNFILES` at it and remove `RUNFILES_MANIFEST_FILE` and `RUNFILES_MANIFEST_ONLY`, whatever the caller's environment holds (default `True`). |

The output is named after the target (`.exe` is added for Windows).
`bazel run` runs it like any binary, and since it needs no runfiles, it
also works as a tool of other rules, as a `data` dependency, or in a
container image.

```starlark
bound_binary(
    name = "migrate",
    binary = "//db:migrate_bin",
    data = ["//db:schema.sql"],
    bound_args = ["--schema", "$(rlocationpath //db:schema.sql)"],
    bound_env = {"MIGRATE_MODE": "production"},
)
```

`./migrate prod.db` then runs `migrate_bin --schema /…/schema.sql prod.db`,
with `/…/schema.sql` the extracted copy.

## Layouts for rule authors

A `BoundInfo` says what a bundle contains, where, and how its program
starts:

| Field | Meaning |
|---|---|
| `layout` | A list of entries made with `bound_layout` (below). |
| `program` | The path in the bundle of the program to run, such as `python/bin/python3` or `node/node.exe`. |
| `args` | Arguments that start it, such as `["-I", "-m", "app.main"]`; those of `bound_binary` and of the caller follow. |
| `env`, `unset` | Variables to set (values like `args`), and to remove. |
| `env_prepend`, `env_append` | List variables such as `PATH`: each name with a list of entries (values like `args`, but not `RUNTIME_ARGS`) put before or after the caller's value, joined with the platform's separator. A name is bound one way only. |
| `runfiles_dir` | The path in the bundle of a runfiles tree, if the layout has one (for data a program finds through a runfiles library, `runfile()` values and `bound_binary`'s `data`); `RUNFILES_DIR` then points at it. |

A rule returns one next to its other providers: `bound_binary` then binds
its targets that way. That costs the rule nothing: a `BoundInfo` is data,
with no actions and no toolchain, and nothing is built unless something
binds it. Rules can also bind themselves (see
[`bound_context`](#your-own-rules-bound_context)).

The entries place files at paths in the bundle, and they hold depsets as
they are: nothing is flattened while rules are analyzed. Paths are
computed when the action runs, by functions that rules_bound gives
`Args.map_each`, so a layout of a hundred thousand files costs analysis no
more than one of ten.

| Entry | Places |
|---|---|
| `bound_layout.files(files, dest = "", strip_prefix = None, unmatched = "error", exclude = None)` | Each File of a depset (or list) at `dest/` + its runfiles path (`_main/pkg/a.py`, `pip_six/site-packages/six.py`), from which the longest of the `strip_prefix` directories containing it is removed: import roots, a toolchain's repository, a package root. Files under none of them are an error, left out (`"skip"`) or kept whole (`"keep"`); `exclude` leaves out runfiles paths and the directories under them. Tree artifacts are expanded file by file. |
| `bound_layout.file(path, file)` | One File at `path`; a tree artifact's files under it. |
| `bound_layout.symlink(path, target)` | A symbolic link at `path` to `target`, another path in the bundle; the link is relative. |
| `bound_layout.symlinks(links, dest = "")` | Many links: a depset (or list) of `(path, target)` pairs, such as the links of a `node_modules` tree, collected from dependencies. |
| `bound_layout.directory(path)` | A directory, empty unless other entries fill it. |
| `bound_layout.runfiles(dest, runfiles, repo_mapping = None)` | A Bazel runfiles tree at `dest`, as runfiles libraries expect it. |

Symbolic links declared with `ctx.actions.declare_symlink` are bundled as
links. On Windows, where creating symbolic links needs a privilege, bound
makes a link a junction (to a directory) or a hard link (to a file) for
users who lack it: what pnpm does, and what Node.js and other programs
follow like links.

Values of `args`, `env` and list entries: strings are literal; `bundle_path(path)` is the
absolute path of `path` in the extracted bundle; `runfile(rlocationpath)`
that of a file in the runfiles tree, as is a File; `raw(text)` is bound's
own syntax; `RUNTIME_ARGS` marks where the run-time arguments go.
`rlocation(file)` gives a File's runfiles path, whose first component is its
repository. `runfiles_bound_info(executable)` returns the `BoundInfo` of
Bazel's own layout, to start from or to fall back on.

### Python: an installed application

What a Python ruleset can do with rules_python's providers: the
interpreter where its distribution puts it, and the application with its
dependencies in the interpreter's own `site-packages`, where `pip install`
would put them. Python finds everything by itself; there is no runfiles
tree, no `PYTHONPATH` and no bootstrap script. (Complete in
[e2e/layout/py.bzl](e2e/layout/py.bzl), with a pip dependency.)

```starlark
load("@rules_bound//bound:defs.bzl", "BoundInfo", "bound_layout", "rlocation")

def _py_bound_layout_impl(ctx):
    binary = ctx.attr.binary
    runtime = binary[PyRuntimeInfo]
    executable = binary[PyExecutableInfo]
    interpreter = rlocation(runtime.interpreter)       # <repo>/bin/python3 or <repo>/python.exe
    repository = interpreter.split("/")[0]
    site_packages = "python/lib/python3.12/site-packages"   # python/Lib/site-packages on Windows
    roots = binary[PyInfo].imports.to_list() + [ctx.workspace_name]
    return [BoundInfo(
        layout = [
            bound_layout.files(runtime.files, dest = "python", strip_prefix = repository),
            bound_layout.file("python" + interpreter[len(repository):], runtime.interpreter),
            bound_layout.files(
                executable.app_runfiles.files,   # the files a virtual environment would hold
                dest = site_packages,
                strip_prefix = roots,            # each file relative to its import root
                unmatched = "skip",
            ),
        ],
        program = "python" + interpreter[len(repository):],
        args = ["-I", "-m", "app.main"],         # computed from executable.main in the example
    )]
```

### JavaScript: a `node_modules` tree

What a JavaScript ruleset can do: `node`, the application, and a
pnpm-style store of packages (tree artifacts) linked into `node_modules`,
so that Node.js's own resolution finds each package's dependencies next to
it, from real paths, as with pnpm. No patched `require`, no loader, no
runfiles. (Complete in [e2e/layout/js.bzl](e2e/layout/js.bzl).)

```starlark
def _js_bound_layout_impl(ctx):
    node = ctx.toolchains["@rules_nodejs//nodejs:runtime_toolchain_type"].nodeinfo.node
    deps = [dep[JsPackageInfo] for dep in ctx.attr.deps]
    return [BoundInfo(
        layout = [
            bound_layout.file("node/bin/node", node),   # node/node.exe on Windows
            bound_layout.files(ctx.files.srcs, dest = "app", strip_prefix = app_dir),
            # The store: node_modules/.store/<name>@<version>/node_modules/<name>/...
            bound_layout.files(depset(transitive = [dep.directories for dep in deps]), dest = "app", strip_prefix = here),
            # node_modules/<name> -> .store/..., and each package's links to its dependencies.
            bound_layout.symlinks(depset(direct_links, transitive = [dep.links for dep in deps]), dest = "app"),
        ],
        program = "node/bin/node",
        args = [bundle_path("app/main.js")],
        # Programs node starts find the same node.
        env_prepend = {"PATH": [bundle_path("node/bin")]},
    )]
```

## Your own rules: `bound_context`

Rules can produce bound executables themselves. `bound_context(ctx)` adapts
the rule's context: `bind()` registers the action and returns the File.

```starlark
load("@rules_bound//bound:defs.bzl", "BOUND_TOOLCHAIN_TYPE", "bound_context")

def _configured_tool_impl(ctx):
    config = ctx.actions.declare_file(ctx.label.name + ".cfg")
    ctx.actions.write(config, "greeting = {}\n".format(ctx.attr.greeting))
    bound = bound_context(ctx)
    result = bound.bind(
        executable = ctx.attr.tool,              # a Target, a File or a BoundInfo
        args = ["--config", config, bound.runtime_args, "--verbose"],
        env = {"TOOL_MODE": "configured"},
    )
    return [DefaultInfo(executable = result.executable)]

configured_tool = rule(
    implementation = _configured_tool_impl,
    attrs = {
        "greeting": attr.string(),
        "tool": attr.label(executable = True, cfg = "target"),
    },
    executable = True,
    toolchains = [BOUND_TOOLCHAIN_TYPE],
)
```

`bind(executable, layout = [], runfiles = None, output = None, args = [],
env = {}, unset = [], env_prepend = {}, env_append = {}, bundle = "shared",
cwd = "inherit", runfiles_env = None, mnemonic = "Bound")`:

* `executable`: a Target (its `BoundInfo` if it has one, otherwise the
  program and its runfiles), a File (that program alone), or a `BoundInfo`.
* `layout`: more entries; `runfiles`: more runfiles, for the runfiles tree.
* `args` and `env` follow those of the `BoundInfo` (a variable of `env`
  overrides one of the `BoundInfo`).
* `env_prepend` and `env_append` wrap the `BoundInfo`'s entries of the same
  name: the caller's prepend entries come first and its append entries
  last. A name the caller sets or unsets replaces the `BoundInfo`'s binding
  of it, whatever its kind, and one party binds a name one way only. Names
  compare case-insensitively, as bound compares them.
* `cwd`: `"inherit"`, `"bundle"`, or `bundle_path(DIR)` for a directory the
  layout holds.
* `runfiles_env`: by default, when the layout has a runfiles tree.
* `output`: the File to write; by default the rule's name, with `.exe` for
  Windows.
* It returns a struct with `executable` (the File), `program` (its path in
  the bundle) and `runfiles_dir` (the runfiles tree's path, or None).

`bound.toolchain` holds the resolved toolchain (`bound`, `launcher`,
`exe_suffix`); `bound.layout`, `bound.bundle_path`, `bound.runfile`,
`bound.raw`, `bound.runtime_args` and `bound.rlocation` are the helpers
above.

## How it works

`bind` writes one action running `bound build`. The layout becomes an
`--include-list` file of `DEST=SOURCE` lines (a file or directory to
bundle, or `@link:TARGET` for a link, `@dir` for a directory), written when
the action runs from the entries' depsets, and the program is `@bundle:` its
path. Every file is checked against its SHA-256 when it is extracted; see
bound's documentation for the format, the security model and the
platforms.

For Bazel's own layout, the program is placed at its own name with its
runfiles tree next to it, at `<name>.runfiles/`, including the
`_repo_mapping` file that bzlmod runfiles libraries read, and, for Bazel's
Windows launchers, the script they run from beside them (a `py_binary`'s
`<name>`, next to `<name>.exe`). The tree is built from the target's
runfiles as Bazel knows them, not from a runfiles directory, so it works
where Bazel creates no runfiles trees (Windows by default).

## Notes

* **Python with Bazel's own layout.** rules_python's default bootstrap
  starts a `py_binary` through `#!/usr/bin/env python3`, so the destination
  needs some Python 3 to reach the bundled interpreter; with
  `--@rules_python//python/config_settings:bootstrap_impl=script` it starts
  through a shell script and needs none. A `BoundInfo` layout like the one
  above needs neither.
* **Shared bundles are read-only**, like runfiles. A program that writes
  into its bundle needs `bundle = "private"`.
* **The working directory** is the caller's, not the runfiles directory as
  under `bazel run`: programs should find their files through their
  language's rules, a runfiles library, or arguments.
* **Paths in a bundle** cannot contain `=` or newlines (the build fails
  saying which).

## Development

`e2e/` is a workspace that uses these rules with `sh_binary`, `py_binary`,
`cc_binary`, a rule of its own, and the Python and JavaScript layouts of
`e2e/layout/`, with bound built from a checkout next to it. CI runs it on
Linux and Windows, on x86_64 and aarch64, and on macOS (Apple silicon):

```sh
git clone https://github.com/bound-rs/bound && cd bound
git clone https://github.com/bound-rs/rules_bound
cargo build --release          # bound's binaries, which e2e/MODULE.bazel points at
rules_bound/e2e/run.sh         # bazel build and test, then the executables outside Bazel
```

On Windows, run it from Git's bash, with `BAZEL_SH` set to that bash and a
short output root (`startup --output_user_root=C:/b` in `~/.bazelrc`).

`bcr_test/` is the module the Bazel Central Registry tests each release
with: a `cc_binary` bound by the default toolchain, the released binaries.
CI runs it too.

To release: add the bound version to `bound/private/versions.bzl` (the
output of `scripts/checksums.sh VERSION`) and make it `DEFAULT_VERSION`,
set the version in `MODULE.bazel`, then push a tag `vX.Y.Z`. A workflow
publishes the source archive that the registry entry points to; `.bcr/`
holds the templates for that entry.

## License

Apache License 2.0; see [LICENSE](LICENSE).
