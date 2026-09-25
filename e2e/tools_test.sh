#!/usr/bin/env bash
# --- begin runfiles.bash initialization v3 ---
set -uo pipefail; set +e; f=bazel_tools/tools/bash/runfiles/runfiles.bash
source "${RUNFILES_DIR:-/dev/null}/$f" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "${RUNFILES_MANIFEST_FILE:-/dev/null}" | cut -f2- -d' ')" 2>/dev/null || \
  source "$0.runfiles/$f" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "$0.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "$0.exe.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \
  { echo>&2 "ERROR: cannot find $f"; exit 1; }; f=; set -e
# --- end runfiles.bash initialization v3 ---

# The test's own runfiles variables are set; the bound tools ignore them.
tool() {
  local path
  path="$(rlocation "_main/$1")"
  [[ -e "$path" ]] || path="$(rlocation "_main/$1.exe")"
  echo "$path"
}
check() {
  local expected="$1"; shift
  local out
  out="$("$@")"
  if [[ "$out" != *"$expected"* ]]; then
    echo "FAIL: $* printed: $out (expected $expected)" >&2
    exit 1
  fi
  echo "ok: $out"
}
check "Hello, from bound world" "$(tool sh/greet_bound)" world
check "Bound report: runfiles, interpreter, dependencies" "$(tool py/report_bound)"
check "Hello from C++ | extra data | x | (end)" "$(tool cc/hello_bound)" x
check "mode=configured config=greeting = Hi args=a @literal" "$(tool custom/configured)" a
