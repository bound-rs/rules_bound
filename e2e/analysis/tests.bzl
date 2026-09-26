"""Analysis tests of bind: how cwd renders, how a caller's bindings combine
with a BoundInfo's, and what bind and BoundInfo refuse.

They read the options of the bind action (`--cwd`, `--env`, `--unset`,
`--env-prepend`, `--env-append`) in order. The fixtures are manual: nothing
builds them, and the refused ones do not even analyze.
"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@rules_bound//bound:defs.bzl", "BOUND_TOOLCHAIN_TYPE", "BoundInfo", "RUNTIME_ARGS", "bound_binary", "bound_context", "bound_layout", "bundle_path", "runfile")

# Each case: the BoundInfo's bindings and the caller's bind() arguments, then
# either the options of the bind action, as "OPTION VALUE", or the refusal.
_CASES = {
    "cwd_inherit": struct(
        info = {},
        bind = {"cwd": "inherit"},
        options = ["--cwd inherit"],
    ),
    "cwd_bundle": struct(
        info = {},
        bind = {"cwd": "bundle"},
        options = ["--cwd bundle"],
    ),
    "cwd_bundle_path": struct(
        info = {},
        bind = {"cwd": bundle_path("work")},
        options = ["--cwd @bundle:work"],
    ),
    # List entries render like other values: a bundled path, and a literal
    # whose leading @ is escaped.
    "list_values": struct(
        info = {"env_prepend": {"PATH": [bundle_path("tools"), "@literal"]}},
        bind = {},
        # buildifier: disable=canonical-repository (@@ is bound's escaped @)
        options = ["--cwd inherit", "--env-prepend PATH=@bundle:tools", "--env-prepend PATH=@@literal"],
    ),
    # A caller's prepend entries go before the BoundInfo's, its append
    # entries after them.
    "lists_wrap": struct(
        info = {"env_prepend": {"PATH": ["info-before"]}, "env_append": {"PATH": ["info-after"]}},
        bind = {"env_prepend": {"PATH": ["caller-before"]}, "env_append": {"PATH": ["caller-after"]}},
        options = [
            "--cwd inherit",
            "--env-prepend PATH=caller-before",
            "--env-prepend PATH=info-before",
            "--env-append PATH=info-after",
            "--env-append PATH=caller-after",
        ],
    ),
    # Names compare case-insensitively: the caller's `path` joins the
    # BoundInfo's `PATH`, which keeps its spelling.
    "lists_case": struct(
        info = {"env_prepend": {"PATH": ["info"]}},
        bind = {"env_prepend": {"path": ["caller"]}},
        options = ["--cwd inherit", "--env-prepend PATH=caller", "--env-prepend PATH=info"],
    ),
    # A caller's env or unset of a name replaces the BoundInfo's list of it,
    # whatever the case.
    "env_replaces_list": struct(
        info = {"env_prepend": {"PATH": ["info"]}},
        bind = {"env": {"Path": "fixed"}},
        options = ["--cwd inherit", "--env Path=fixed"],
    ),
    "unset_replaces_list": struct(
        info = {"env_append": {"PATH": ["info"]}},
        bind = {"unset": ["PATH"]},
        options = ["--cwd inherit", "--unset PATH"],
    ),
    # And a caller's list replaces the BoundInfo's env or unset of the name.
    "list_replaces_env": struct(
        info = {"env": {"PATH": "info"}},
        bind = {"env_prepend": {"PATH": ["caller"]}},
        options = ["--cwd inherit", "--env-prepend PATH=caller"],
    ),
    "list_replaces_unset": struct(
        info = {"unset": ["PATH"]},
        bind = {"env_append": {"PATH": ["caller"]}},
        options = ["--cwd inherit", "--env-append PATH=caller"],
    ),
    # One party's prepend and append of one name are one binding.
    "prepend_and_append": struct(
        info = {"env_prepend": {"X": ["a"]}, "env_append": {"X": ["b"]}},
        bind = {"env_prepend": {"Y": ["c"]}, "env_append": {"Y": ["d"]}},
        options = ["--cwd inherit", "--env-prepend X=a", "--env-append X=b", "--env-prepend Y=c", "--env-append Y=d"],
    ),
    "refuses_a_name_bound_two_ways": struct(
        info = {},
        bind = {"env": {"X": "1"}, "env_prepend": {"x": ["a"]}},
        refusal = "is bound more than one way",
    ),
    "refuses_a_boundinfo_name_bound_two_ways": struct(
        info = {"unset": ["X"], "env_append": {"x": ["a"]}},
        bind = {},
        refusal = "BoundInfo: the variable",
    ),
    "refuses_an_empty_list": struct(
        info = {},
        bind = {"env_append": {"X": []}},
        refusal = "X has no entries",
    ),
    "refuses_a_list_that_is_not_one": struct(
        info = {},
        bind = {"env_prepend": {"X": "a"}},
        refusal = "must be a list of entries",
    ),
    "refuses_runtime_args_in_a_list": struct(
        info = {},
        bind = {"env_prepend": {"X": [RUNTIME_ARGS]}},
        refusal = "RUNTIME_ARGS has no place in a list variable",
    ),
    "refuses_a_runfile_without_a_runfiles_tree": struct(
        info = {},
        bind = {"env_append": {"X": [runfile("_main/x")]}},
        refusal = "needs a runfiles tree",
    ),
    "refuses_another_cwd": struct(
        info = {},
        bind = {"cwd": "elsewhere"},
        refusal = "cwd: expected",
    ),
}

def _bind_case_impl(ctx):
    case = _CASES[ctx.attr.case]
    info = BoundInfo(layout = [bound_layout.file("tool", ctx.file._program)], program = "tool", **case.info)
    result = bound_context(ctx).bind(info, **case.bind)
    return [DefaultInfo(files = depset([result.executable]))]

_bind_case = rule(
    implementation = _bind_case_impl,
    attrs = {
        "case": attr.string(mandatory = True),
        "_program": attr.label(default = ":tool.txt", allow_single_file = True),
    },
    toolchains = [BOUND_TOOLCHAIN_TYPE],
)

_OPTIONS = ["--cwd", "--env", "--unset", "--env-prepend", "--env-append"]

def _options(argv):
    """The bind action's directory and environment options, in order."""
    options = []
    skip = False
    for index, argument in enumerate(argv):
        if skip:
            skip = False
        elif argument == "--":
            break
        elif argument in _OPTIONS and index + 1 < len(argv):
            options.append("{} {}".format(argument, argv[index + 1]))
            skip = True
    return options

def _matches(pattern, option):
    """Whether an option matches a pattern, where one `*` stands for anything."""
    if "*" not in pattern:
        return pattern == option
    head, tail = pattern.split("*", 1)
    return len(option) >= len(head) + len(tail) and option.startswith(head) and option.endswith(tail)

def _bind_options_test_impl(ctx):
    env = analysistest.begin(ctx)
    binds = [action for action in analysistest.target_actions(env) if action.mnemonic == "Bound"]
    asserts.equals(env, 1, len(binds))
    if binds:
        options = _options(binds[0].argv)
        expected = ctx.attr.options
        matched = len(options) == len(expected) and all([_matches(pattern, option) for pattern, option in zip(expected, options)])
        asserts.true(env, matched, "expected options {}, got {}".format(expected, options))
    return analysistest.end(env)

_bind_options_test = analysistest.make(_bind_options_test_impl, attrs = {"options": attr.string_list()})

def _bind_refusal_test_impl(ctx):
    env = analysistest.begin(ctx)
    asserts.expect_failure(env, ctx.attr.message)
    return analysistest.end(env)

_bind_refusal_test = analysistest.make(_bind_refusal_test_impl, expect_failure = True, attrs = {"message": attr.string()})

def bind_test_suite(name):
    """The analysis tests of bind, with their fixtures.

    Args:
      name: the test suite's name; the tests and fixtures are named after it.
    """
    tests = []
    for case_name, case in _CASES.items():
        fixture = "{}_{}_fixture".format(name, case_name)
        _bind_case(name = fixture, case = case_name, tags = ["manual"])
        test = "{}_{}".format(name, case_name)
        if hasattr(case, "refusal"):
            _bind_refusal_test(name = test, target_under_test = ":" + fixture, message = case.refusal)
        else:
            _bind_options_test(name = test, target_under_test = ":" + fixture, options = case.options)
        tests.append(":" + test)

    # bound_binary's attributes: a layout's list with the binary's own, and
    # data's runfiles with list entries naming them.
    _bind_options_test(
        name = name + "_js_where",
        target_under_test = "//layout:js_where",
        # node/bin on Unix, node on Windows.
        options = ["--cwd @bundle:app", "--env-prepend PATH=@bundle:node*", "--env-append PATH=@bundle:app"],
    )
    tests.append(":" + name + "_js_where")
    bound_binary(
        name = name + "_data_lists_fixture",
        binary = "//sh:greet",
        data = [":extra.txt"],
        bound_env_prepend = {"EXTRA": ["$(rlocationpath :extra.txt)"]},
        bound_env_append = {"EXTRA": ["@bundle:tail"]},
        cwd = "bundle",
        tags = ["manual"],
    )
    _bind_options_test(
        name = name + "_data_lists",
        target_under_test = ":" + name + "_data_lists_fixture",
        # greet.runfiles on Unix, greet.exe.runfiles on Windows.
        options = [
            "--cwd bundle",
            "--env RUNFILES_DIR=@bundle:greet*.runfiles",
            "--env JAVA_RUNFILES=@bundle:greet*.runfiles",
            "--unset RUNFILES_MANIFEST_FILE",
            "--unset RUNFILES_MANIFEST_ONLY",
            "--env-prepend EXTRA=@bundle:greet*.runfiles/_main/analysis/extra.txt",
            "--env-append EXTRA=@bundle:tail",
        ],
    )
    tests.append(":" + name + "_data_lists")
    native.test_suite(name = name, tests = tests)
