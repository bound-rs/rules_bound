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
    "0.2.0": {
        "linux_aarch64": "e8218bd827b04ff64825c2fc2bb0515f6ea97fe9f04d68471a425259971a07e4",
        "linux_x86_64": "b5eeb61489b52bcd9e1468172518820de15b91641b4b6af2c4dbf7b006bfe294",
        "macos_aarch64": "94687b3a264b566da9ba88b506d7a5c52253c849b26e6b9fd73f74159862ae3c",
        "windows_aarch64": "926a535e6d80ceb5bab8731bddd4a075e9a2a16f9ca727a277e6107e286edd10",
        "windows_x86_64": "34cb4a731735ae5c6a17322734eb55806cbb4858a94133d8dc02c440f2ccf51b",
    },
}

# The version used when the root module does not choose one.
DEFAULT_VERSION = "0.2.0"

URL_TEMPLATE = "https://github.com/bound-rs/bound/releases/download/v{version}/bound-{version}-{platform}.{archive}"
