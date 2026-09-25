"""Reads a data file through the runfiles library and reports it."""

import json
import os
import sys

from python.runfiles import runfiles

r = runfiles.Create()
# The apparent repository name, which the bundled _repo_mapping resolves.
with open(r.Rlocation("rules_bound_e2e/py/data.json"), encoding="utf-8") as source:
    items = json.load(source)["items"]
title = os.environ.get("REPORT_TITLE", "report")
print(f"{title}: {', '.join(items)} (Python {sys.version_info.major}.{sys.version_info.minor})")
