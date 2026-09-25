"""Checks that the application runs as an installed Python application.

The interpreter at python/, this package and its dependencies in the
interpreter's own site-packages, `python -I -m app.main`: no runfiles, no
PYTHONPATH, no bootstrap script.
"""

import importlib.metadata
import os
import sys
import sysconfig

import greeting
import idna


def _within(path: str, directory: str) -> bool:
    return os.path.commonpath([os.path.realpath(path), os.path.realpath(directory)]) == os.path.realpath(directory)


def main() -> None:
    site_packages = sysconfig.get_paths()["purelib"]
    checks = {
        "the interpreter is the bundled one": _within(sys.executable, os.path.join(os.environ["BOUND_ROOT"], "python")),
        "the application is in site-packages": _within(__file__, site_packages),
        "its dependencies are in site-packages": _within(idna.__file__, site_packages),
        "sys.path is the interpreter's own": all(_within(entry, sys.prefix) for entry in sys.path),
        "isolated mode": sys.flags.isolated == 1,
    }
    failed = [name for name, ok in checks.items() if not ok]
    status = "FAILED: " + "; ".join(failed) if failed else "installed layout"
    print(
        f"{greeting.text()} | idna {importlib.metadata.version('idna')}: {idna.encode('bücher.example').decode()}"
        f" | {status} | {' '.join(sys.argv[1:])}"
    )


if __name__ == "__main__":
    main()
