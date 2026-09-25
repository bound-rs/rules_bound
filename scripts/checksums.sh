#!/usr/bin/env bash
# Prints the entry of bound/private/versions.bzl for a release of bound,
# from the SHA256SUMS file published with it.
#
#   scripts/checksums.sh 0.1.0
set -euo pipefail
version="${1:?usage: scripts/checksums.sh VERSION}"
sums="$(curl -fsSL "https://github.com/bound-rs/bound/releases/download/v${version}/SHA256SUMS")"
echo "    \"${version}\": {"
while read -r sha256 archive; do
  # bound-VERSION-PLATFORM.tar.gz or .zip
  platform="${archive#bound-"${version}"-}"
  platform="${platform%.tar.gz}"
  platform="${platform%.zip}"
  echo "        \"${platform}\": \"${sha256}\","
done <<< "$sums"
echo "    },"
