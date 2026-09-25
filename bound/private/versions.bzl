"""Released versions of bound and the checksums of their archives.

To add a release, run `scripts/checksums.sh VERSION` and paste its output
here. Until a version is listed, use `bound.toolchain(version, sha256s = ...)`
or `bound.local(path)` (see extensions.bzl).
"""

# version -> {platform key -> sha256 of bound-<version>-<platform>.<archive>}
VERSIONS = {
}

# The version used when the root module does not choose one (None: no
# release is known yet, and no toolchain is registered by default).
DEFAULT_VERSION = None

URL_TEMPLATE = "https://github.com/bound-rs/bound/releases/download/v{version}/bound-{version}-{platform}.{archive}"
