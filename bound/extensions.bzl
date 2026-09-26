"""The `bound` module extension: which bound binaries the toolchains use.

rules_bound registers `@bound_toolchains//:all`, which this extension
fills. The root module chooses:

```starlark
bound = use_extension("@rules_bound//bound:extensions.bzl", "bound")

# A released version (checksums built into rules_bound, or given here):
bound.toolchain(version = "0.2.1")

# Or binaries built locally, for the host platform only, e.g. from a bound
# checkout (a path relative to the root module, or absolute):
bound.local(path = "../bound/target/release")
```

A released version provides a toolchain for every pair of supported
execution and target platforms, so builds can produce executables for
other platforms. Without either tag, the default version is used; if
rules_bound knows no release yet, no toolchain is declared and you need
one of the tags, or a toolchain of your own (see toolchain.bzl).
"""

load("//bound/private:platforms.bzl", "PLATFORMS", "constraints")
load("//bound/private:repositories.bzl", "bound_local", "bound_release", "bound_toolchains")
load("//bound/private:versions.bzl", "DEFAULT_VERSION", "URL_TEMPLATE", "VERSIONS")

_toolchain = tag_class(
    doc = "Use a released version of bound.",
    attrs = {
        "version": attr.string(mandatory = True, doc = "The version, such as 0.2.1."),
        "sha256s": attr.string_dict(
            doc = "SHA-256 of each platform's archive (keys such as linux_x86_64, macos_aarch64, windows_x86_64), for versions rules_bound does not know. Platforms left out get no toolchain.",
        ),
        "url_templates": attr.string_list(
            default = [URL_TEMPLATE],
            doc = "Where to download archives from; {version}, {platform} and {archive} are replaced.",
        ),
    },
)

_local = tag_class(
    doc = "Use `bound` and `bound-launcher` from a local directory, for the host platform only.",
    attrs = {
        "path": attr.string(
            mandatory = True,
            doc = "The directory: absolute, or relative to the root module (such as ../bound/target/release).",
        ),
    },
)

def _choice(mctx):
    # The root module decides; other modules' choices apply only when it
    # makes none.
    for module in mctx.modules:
        tags = module.tags.local + module.tags.toolchain
        if len(tags) > 1:
            fail("bound: module {} uses bound.local or bound.toolchain more than once".format(module.name))
        if tags:
            if module.tags.local and not module.is_root:
                fail("bound.local is only for the root module (module {} uses it)".format(module.name))
            return module, tags[0]
    return None, None

def _bound_impl(mctx):
    labels = {
        "toolchain_bzl": str(Label("//bound:toolchain.bzl")),
        "host_constraints_bzl": str(Label("@platforms//host:constraints.bzl")),
        "toolchain_type": str(Label("//bound:toolchain_type")),
    }
    module, tag = _choice(mctx)

    if module and module.tags.local:
        path = tag.path
        if not (path.startswith("/") or (len(path) > 1 and path[1] == ":")):
            root = mctx.path(Label("@@//:MODULE.bazel")).dirname
            path = "{}/{}".format(root, path)
        bound_local(name = "bound_local", path = path)
        bound_toolchains(name = "bound_toolchains", local_repo = "bound_local", **labels)
        return mctx.extension_metadata(reproducible = True)

    version = tag.version if tag else DEFAULT_VERSION
    releases = {}
    if version:
        sha256s = dict(VERSIONS.get(version, {}))
        if tag:
            sha256s.update(tag.sha256s)
        if not sha256s:
            fail("bound {}: rules_bound knows no checksums for this version; pass bound.toolchain(version, sha256s = {{...}})".format(version))
        for platform, sha256 in sha256s.items():
            if platform not in PLATFORMS:
                fail("bound: unknown platform {} (known: {})".format(platform, ", ".join(PLATFORMS.keys())))
            name = "bound_" + platform
            bound_release(
                name = name,
                version = version,
                platform = platform,
                sha256 = sha256,
                url_templates = tag.url_templates if tag else [URL_TEMPLATE],
            )
            releases[platform] = name
    bound_toolchains(
        name = "bound_toolchains",
        releases = releases,
        constraints = {platform: " ".join([str(Label(c)) for c in constraints(platform)]) for platform in releases},
        **labels
    )
    return mctx.extension_metadata(reproducible = True)

bound = module_extension(
    implementation = _bound_impl,
    doc = "Provides the bound toolchains (see the module documentation).",
    tag_classes = {
        "toolchain": _toolchain,
        "local": _local,
    },
)
