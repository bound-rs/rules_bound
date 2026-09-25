"""The bound toolchain.

A bound toolchain pairs the `bound` command line, which runs on the
execution platform, with a `bound-launcher`, the start of every executable
bound writes, for the target platform. The module extension in
extensions.bzl declares toolchains for released binaries; declare your own
with `bound_toolchain` and `toolchain()` to use others:

```starlark
load("@rules_bound//bound:toolchain.bzl", "bound_toolchain")

bound_toolchain(
    name = "my_bound",
    bound = "//tools:bound",
    launcher = "//tools:bound-launcher",
)

toolchain(
    name = "my_bound_toolchain",
    exec_compatible_with = ["@platforms//os:linux", "@platforms//cpu:x86_64"],
    target_compatible_with = ["@platforms//os:linux", "@platforms//cpu:x86_64"],
    toolchain = ":my_bound",
    toolchain_type = "@rules_bound//bound:toolchain_type",
)
```
"""

def _bound_toolchain_impl(ctx):
    launcher = ctx.file.launcher
    return [platform_common.ToolchainInfo(
        bound = ctx.attr.bound[DefaultInfo].files_to_run,
        launcher = launcher,
        # The launcher's platform is the target's: Windows runs .exe files.
        exe_suffix = ".exe" if launcher.basename.lower().endswith(".exe") else "",
    )]

bound_toolchain = rule(
    implementation = _bound_toolchain_impl,
    doc = "The `bound` command line and the launcher for one target platform.",
    attrs = {
        "bound": attr.label(
            doc = "The `bound` executable, for the execution platform.",
            mandatory = True,
            executable = True,
            allow_single_file = True,
            cfg = "exec",
        ),
        "launcher": attr.label(
            doc = "The `bound-launcher` executable, for the target platform (`bound-launcher.exe` for Windows).",
            mandatory = True,
            allow_single_file = True,
        ),
    },
)
