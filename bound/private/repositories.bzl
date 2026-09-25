"""Repository rules that provide bound binaries and declare toolchains."""

load(":platforms.bzl", "PLATFORMS")

_BINARIES_BUILD = """\
package(default_visibility = ["//visibility:public"])

exports_files(["bound{exe}", "bound-launcher{exe}"])
"""

def _bound_release_impl(rctx):
    info = PLATFORMS[rctx.attr.platform]
    name = "bound-{}-{}".format(rctx.attr.version, rctx.attr.platform)
    rctx.download_and_extract(
        url = [
            template.format(version = rctx.attr.version, platform = rctx.attr.platform, archive = info.archive)
            for template in rctx.attr.url_templates
        ],
        sha256 = rctx.attr.sha256,
        stripPrefix = name,
    )
    rctx.file("BUILD.bazel", _BINARIES_BUILD.format(exe = info.exe))

bound_release = repository_rule(
    implementation = _bound_release_impl,
    doc = "The released bound binaries for one platform.",
    attrs = {
        "version": attr.string(mandatory = True),
        "platform": attr.string(mandatory = True, values = PLATFORMS.keys()),
        "sha256": attr.string(mandatory = True),
        "url_templates": attr.string_list(mandatory = True),
    },
)

def _bound_local_impl(rctx):
    exe = ".exe" if "windows" in rctx.os.name.lower() else ""
    directory = rctx.path(rctx.attr.path)
    for name in ["bound", "bound-launcher"]:
        binary = directory.get_child(name + exe)
        if not binary.exists:
            fail("bound.local: {} does not exist; build bound first (cargo build --release in a bound checkout)".format(binary))
        rctx.watch(binary)
        rctx.symlink(binary, name + exe)
    rctx.file("BUILD.bazel", _BINARIES_BUILD.format(exe = exe))

bound_local = repository_rule(
    implementation = _bound_local_impl,
    doc = "bound binaries from a local directory, for the host platform.",
    attrs = {
        "path": attr.string(mandatory = True, doc = "An absolute path."),
    },
    local = True,
)

def _toolchain_targets(name, bound, launcher, exec_constraints, target_constraints, toolchain_type, bound_toolchain):
    return """
{bound_toolchain}(
    name = "{name}",
    bound = "{bound}",
    launcher = "{launcher}",
)

toolchain(
    name = "{name}_toolchain",
    exec_compatible_with = {exec_constraints},
    target_compatible_with = {target_constraints},
    toolchain = ":{name}",
    toolchain_type = "{toolchain_type}",
)
""".format(
        bound_toolchain = bound_toolchain,
        name = name,
        bound = bound,
        launcher = launcher,
        exec_constraints = exec_constraints,
        target_constraints = target_constraints,
        toolchain_type = toolchain_type,
    )

def _bound_toolchains_impl(rctx):
    content = [
        'load("{}", "bound_toolchain")'.format(rctx.attr.toolchain_bzl),
        "",
        'package(default_visibility = ["//visibility:public"])',
    ]
    if rctx.attr.local_repo:
        content.insert(0, 'load("{}", "HOST_CONSTRAINTS")'.format(rctx.attr.host_constraints_bzl))
        exe = ".exe" if "windows" in rctx.os.name.lower() else ""
        content.append(_toolchain_targets(
            name = "local",
            bound = "@{}//:bound{}".format(rctx.attr.local_repo, exe),
            launcher = "@{}//:bound-launcher{}".format(rctx.attr.local_repo, exe),
            exec_constraints = "HOST_CONSTRAINTS",
            target_constraints = "HOST_CONSTRAINTS",
            toolchain_type = rctx.attr.toolchain_type,
            bound_toolchain = "bound_toolchain",
        ))
    for exec_platform, exec_repo in rctx.attr.releases.items():
        for target_platform, target_repo in rctx.attr.releases.items():
            content.append(_toolchain_targets(
                name = "{}_to_{}".format(exec_platform, target_platform),
                bound = "@{}//:bound{}".format(exec_repo, PLATFORMS[exec_platform].exe),
                launcher = "@{}//:bound-launcher{}".format(target_repo, PLATFORMS[target_platform].exe),
                exec_constraints = repr(rctx.attr.constraints[exec_platform].split(" ")),
                target_constraints = repr(rctx.attr.constraints[target_platform].split(" ")),
                toolchain_type = rctx.attr.toolchain_type,
                bound_toolchain = "bound_toolchain",
            ))
    rctx.file("BUILD.bazel", "\n".join(content) + "\n")

bound_toolchains = repository_rule(
    implementation = _bound_toolchains_impl,
    doc = "Declares a toolchain for every pair of execution and target platform.",
    attrs = {
        "releases": attr.string_dict(doc = "platform -> repository with its released binaries"),
        "constraints": attr.string_dict(doc = "platform -> its constraint labels, separated by spaces"),
        "local_repo": attr.string(doc = "a bound_local repository, for a host toolchain"),
        "toolchain_bzl": attr.string(mandatory = True),
        "host_constraints_bzl": attr.string(mandatory = True),
        "toolchain_type": attr.string(mandatory = True),
    },
)
