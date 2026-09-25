"""A rule of your own that builds a bound executable: the ctx adaptor."""

load("@rules_bound//bound:defs.bzl", "BOUND_TOOLCHAIN_TYPE", "bound_context")

def _configured_tool_impl(ctx):
    # A generated file, bundled and passed by its path.
    config = ctx.actions.declare_file(ctx.label.name + ".cfg")
    ctx.actions.write(config, "greeting = {}\n".format(ctx.attr.greeting))
    bound = bound_context(ctx)
    result = bound.bind(
        executable = ctx.attr.tool,
        args = ["--config", config, bound.runtime_args, "@literal"],
        env = {"TOOL_MODE": "configured"},
        bundle = "private",
    )
    return [DefaultInfo(executable = result.executable, files = depset([result.executable]))]

configured_tool = rule(
    implementation = _configured_tool_impl,
    attrs = {
        "greeting": attr.string(mandatory = True),
        "tool": attr.label(mandatory = True, executable = True, cfg = "target"),
    },
    executable = True,
    toolchains = [BOUND_TOOLCHAIN_TYPE],
)
