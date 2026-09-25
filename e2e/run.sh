#!/usr/bin/env bash
# End-to-end test of rules_bound: builds and tests the targets of this
# workspace, then runs the bound executables the way they are meant to be
# used: copied out of Bazel's output tree, run from another directory, with
# misleading runfiles variables in the environment.
#
#   e2e/run.sh            (BAZEL=... to use another bazel; bazelisk reads .bazelversion)
set -euo pipefail
cd "$(dirname "$0")"
bazel="${BAZEL:-bazel}"

"$bazel" build //...
"$bazel" test //...

bin="$("$bazel" info bazel-bin)"
exe=""
case "$(uname -s)" in MINGW* | MSYS* | CYGWIN*) exe=".exe" ;; esac
work="$(mktemp -d)"
trap 'chmod -R u+w "$work" 2>/dev/null; rm -rf "$work"' EXIT
for target in sh/greet_bound py/report_bound cc/hello_bound custom/configured layout/py_app layout/js_app; do
  cp "$bin/$target$exe" "$work/"
done
mkdir "$work/elsewhere"
cd "$work/elsewhere"

export RUNFILES_DIR=/nonexistent RUNFILES_MANIFEST_FILE=/nonexistent/MANIFEST JAVA_RUNFILES=/nonexistent
export BOUND_CACHE_DIR="$work/cache"

expect() {
  local expected="$1"
  shift
  local out
  out="$("$@")"
  if [[ "$out" != "$expected" ]]; then
    echo "e2e: FAIL: $* printed: $out" >&2
    echo "e2e: expected: $expected" >&2
    exit 1
  fi
  echo "e2e: ok: $*"
}

# Twice: the first run extracts the shared bundles, the second reuses them.
for run in first second; do
  echo "e2e: $run run"
  expect "Hello, from bound world" "../greet_bound$exe" world
  expect "Bound report: runfiles, interpreter, dependencies (Python 3.12)" "../report_bound$exe"
  expect "Hello from C++ | extra data | arg | (end)" "../hello_bound$exe" arg
  expect "mode=configured config=greeting = Hi args=a b @literal" "../configured$exe" a b
  expect "Hello from site-packages | idna 3.10: xn--bcher-kva.example | installed layout | from bound x" "../py_app$exe" x
  expect "a 1.0.0 uses b 2.0.0 | a resolved in node_modules/.store | b is not visible | from bound x" "../js_app$exe" x
done
echo "e2e: all checks passed"
