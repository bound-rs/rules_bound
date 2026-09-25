"""What a Python ruleset can do with rules_bound: lay a py_binary out as an
installed application.

The interpreter goes to `python/`, as its distribution lays it out; the
application and its dependencies go to that interpreter's own
site-packages, where `pip install` would put them; the program is
`python -I -m <main module>`. Python finds everything by itself: there is no
runfiles tree, no PYTHONPATH and no bootstrap script.

This rule returns a BoundInfo and nothing else, so it needs no toolchain;
`bound_binary` binds it. A test fixture of rules_bound, not part of it.
"""

load("@rules_bound//bound:defs.bzl", "BoundInfo", "bound_layout", "rlocation")
load("@rules_python//python:py_executable_info.bzl", "PyExecutableInfo")
load("@rules_python//python:py_info.bzl", "PyInfo")
load("@rules_python//python:py_runtime_info.bzl", "PyRuntimeInfo")

def _relative(path, roots):
    """`path` relative to the deepest of `roots` containing it."""
    best = None
    for root in roots:
        if path.startswith(root + "/") and (best == None or len(root) > len(best)):
            best = root
    return path[len(best) + 1:] if best != None else None

def _py_bound_layout_impl(ctx):
    binary = ctx.attr.binary
    runtime = binary[PyRuntimeInfo]
    executable = binary[PyExecutableInfo]
    windows = ctx.target_platform_has_constraint(ctx.attr._windows[platform_common.ConstraintValueInfo])

    # python-build-standalone, as rules_python downloads it: the repository
    # is the installation (bin/python3, lib/python3.X/ on Unix; python.exe
    # and Lib/ on Windows).
    interpreter = rlocation(runtime.interpreter)
    repository = interpreter.split("/")[0]
    home = "python"
    if windows:
        site_packages = home + "/Lib/site-packages"
    else:
        version = runtime.interpreter_version_info
        site_packages = "{}/lib/python{}.{}/site-packages".format(home, version.major, version.minor)

    # rules_python's import roots: those of the libraries (pip packages'
    # site-packages directories among them), then the main repository.
    roots = binary[PyInfo].imports.to_list() + [ctx.workspace_name]
    main = _relative(rlocation(executable.main), roots)
    if not main:
        fail("{} is under none of the import roots".format(executable.main.short_path))
    if "/__pycache__/" in main:
        # Precompiled without its source: pkg/__pycache__/main.cpython-312.pyc.
        package, _, name = main.partition("/__pycache__/")
        main = package + "/" + name.split(".")[0]
    module = main.rsplit(".", 1)[0].replace("/", ".")

    return [BoundInfo(
        layout = [
            # The interpreter's own packages (pip) and build files are not
            # needed to run the application.
            bound_layout.files(
                runtime.files,
                dest = home,
                strip_prefix = repository,
                exclude = [repository + "/" + path for path in ("include", "share", site_packages[len(home) + 1:])],
            ),
            bound_layout.file(home + interpreter[len(repository):], runtime.interpreter),
            # app_runfiles: the files a virtual environment would hold (the
            # application's, its libraries' and their data), each placed
            # relative to its import root. What is under none is left out,
            # and so is rules_python's own virtual environment.
            bound_layout.files(
                executable.app_runfiles.files,
                dest = site_packages,
                strip_prefix = roots,
                unmatched = "skip",
                exclude = "{}/{}/_{}.venv".format(ctx.workspace_name, binary.label.package, binary.label.name),
            ),
        ],
        program = home + interpreter[len(repository):],
        args = executable.interpreter_args + ["-I", "-m", module],
    )]

py_bound_layout = rule(
    implementation = _py_bound_layout_impl,
    doc = "Lays out a py_binary as an installed application (see the module docs).",
    attrs = {
        "binary": attr.label(mandatory = True, providers = [PyExecutableInfo, PyInfo, PyRuntimeInfo]),
        "_windows": attr.label(default = "@platforms//os:windows"),
    },
)
