"""The platforms bound is released for."""

# Keys name the release archives, bound-<version>-<key>.<ext>; each archive
# holds a directory of the same name with `bound` and `bound-launcher`.
PLATFORMS = {
    "linux_x86_64": struct(os = "linux", cpu = "x86_64", archive = "tar.gz", exe = ""),
    "linux_aarch64": struct(os = "linux", cpu = "aarch64", archive = "tar.gz", exe = ""),
    "macos_aarch64": struct(os = "macos", cpu = "aarch64", archive = "tar.gz", exe = ""),
    "windows_x86_64": struct(os = "windows", cpu = "x86_64", archive = "zip", exe = ".exe"),
    "windows_aarch64": struct(os = "windows", cpu = "aarch64", archive = "zip", exe = ".exe"),
}

def constraints(platform):
    """The @platforms constraints of a platform key.

    Args:
      platform: a key of PLATFORMS.

    Returns:
      A list of constraint labels (as strings).
    """
    info = PLATFORMS[platform]
    return ["@platforms//os:" + info.os, "@platforms//cpu:" + info.cpu]
