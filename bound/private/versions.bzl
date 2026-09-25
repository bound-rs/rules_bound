"""Released versions of bound and the checksums of their archives.

To add a release, run `scripts/checksums.sh VERSION` and paste its output
here. Until a version is listed, use `bound.toolchain(version, sha256s = ...)`
or `bound.local(path)` (see extensions.bzl).
"""

# version -> {platform key -> sha256 of bound-<version>-<platform>.<archive>}
VERSIONS = {
    "0.1.0": {
        "linux_aarch64": "0e73891af9acd4600f142cdd3ea9600bf808befa573f41ff8e0f9248407c0224",
        "linux_x86_64": "1eb207a38d32e4e50714665973cf650c1600048475a23046cce2017f5d83c597",
        "macos_aarch64": "3df2a3ab704be1094b54414514e436034a74156b5886d9514b91907de891d657",
        "windows_aarch64": "a8a197cbb7a799dd13c7659f6ffcdb582d7f614d9632f57a9fb8c5d51d46ae81",
        "windows_x86_64": "17e309f58401fc6b7394da1c0041e2f76cc5893e855061e415f421fb01362600",
    },
}

# The version used when the root module does not choose one.
DEFAULT_VERSION = "0.1.0"

URL_TEMPLATE = "https://github.com/bound-rs/bound/releases/download/v{version}/bound-{version}-{platform}.{archive}"
