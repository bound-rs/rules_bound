"""What a JavaScript ruleset can do with rules_bound: lay a program out with a
node_modules tree, the way pnpm (and rules_js) do.

Each package is a directory (a tree artifact) in a store,
`node_modules/.store/<name>@<version>/node_modules/<name>`, next to links to
its own dependencies; the application's `node_modules/<name>` are links into
the store. Node resolves through the links by itself, from real paths, so
each package sees its own dependencies and nothing else. The program is
`node main.js`: no runfiles, no patched `require`, no loader.

The links are collected in depsets and computed when the action runs
(`bound_layout.symlinks`), as a ruleset would for large dependency graphs.
(On Windows, bound makes them symbolic links, or junctions where the user
may not create those, as pnpm does.) A test fixture of rules_bound, not part
of it.
"""

load("@rules_bound//bound:defs.bzl", "BoundInfo", "bound_layout", "bundle_path", "rlocation")

JsPackageInfo = provider(
    doc = "A package in the store, with its dependencies'.",
    fields = {
        "name": "The package name.",
        "store": "The store directory holding it and links to its dependencies, relative to node_modules' parent.",
        "directories": "depset of the tree artifacts of the package and its dependencies.",
        "links": "depset of (path, target) links between packages in the store.",
    },
)

def _js_package_impl(ctx):
    name = ctx.attr.package_name
    store = "node_modules/.store/{}@{}/node_modules".format(name, ctx.attr.version)
    directory = ctx.actions.declare_directory(store + "/" + name)
    prefix = ctx.label.package + "/" + ctx.attr.root + "/"
    commands = ["mkdir -p \"$1\""]
    for src in ctx.files.srcs:
        if not src.short_path.startswith(prefix):
            fail("{} is not under {}".format(src.short_path, prefix))
        relative = src.short_path[len(prefix):]
        commands.append("mkdir -p \"$1/$(dirname '{}')\" && cp '{}' \"$1/{}\"".format(relative, src.path, relative))
    ctx.actions.run_shell(
        outputs = [directory],
        inputs = ctx.files.srcs,
        command = " && ".join(commands),
        arguments = [directory.path],
        mnemonic = "JsPackage",
    )
    deps = [dep[JsPackageInfo] for dep in ctx.attr.deps]
    return [JsPackageInfo(
        name = name,
        store = store,
        directories = depset([directory], transitive = [dep.directories for dep in deps]),
        links = depset(
            [(store + "/" + dep.name, dep.store + "/" + dep.name) for dep in deps],
            transitive = [dep.links for dep in deps],
        ),
    )]

js_package = rule(
    implementation = _js_package_impl,
    attrs = {
        "package_name": attr.string(mandatory = True),
        "version": attr.string(mandatory = True),
        "root": attr.string(mandatory = True, doc = "The package's directory, relative to this package."),
        "srcs": attr.label_list(allow_files = True),
        "deps": attr.label_list(providers = [JsPackageInfo]),
    },
)

_NODE_TOOLCHAIN = "@rules_nodejs//nodejs:runtime_toolchain_type"

def _js_bound_layout_impl(ctx):
    node = ctx.toolchains[_NODE_TOOLCHAIN].nodeinfo.node
    windows = ctx.target_platform_has_constraint(ctx.attr._windows[platform_common.ConstraintValueInfo])
    program = "node/node.exe" if windows else "node/bin/node"
    deps = [dep[JsPackageInfo] for dep in ctx.attr.deps]
    package = rlocation(ctx.files.srcs[0]).rsplit("/", 1)[0] if ctx.files.srcs else ctx.workspace_name
    here = ctx.workspace_name + "/" + ctx.label.package
    return [BoundInfo(
        layout = [
            bound_layout.file(program, node),
            # The application's files, relative to its directory.
            bound_layout.files(ctx.files.srcs, dest = "app", strip_prefix = package),
            # The store: tree artifacts, expanded file by file.
            bound_layout.files(
                depset(transitive = [dep.directories for dep in deps]),
                dest = "app",
                strip_prefix = here,
            ),
            bound_layout.symlinks(
                depset(
                    [("node_modules/" + dep.name, dep.store + "/" + dep.name) for dep in deps],
                    transitive = [dep.links for dep in deps],
                ),
                dest = "app",
            ),
        ],
        program = program,
        args = [bundle_path("app/" + ctx.attr.entry)],
    )]

js_bound_layout = rule(
    implementation = _js_bound_layout_impl,
    doc = "Lays out a node program with a pnpm-style node_modules tree (see the module docs).",
    attrs = {
        "entry": attr.string(mandatory = True, doc = "The entry point, relative to the directory of `srcs`."),
        "srcs": attr.label_list(allow_files = True),
        "deps": attr.label_list(providers = [JsPackageInfo]),
        "_windows": attr.label(default = "@platforms//os:windows"),
    },
    toolchains = [_NODE_TOOLCHAIN],
)
