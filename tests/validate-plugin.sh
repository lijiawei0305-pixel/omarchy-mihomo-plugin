#!/usr/bin/env bash
set -euo pipefail

# The full Omarchy validator is used whenever it is installed. This small
# fallback keeps manifest and entry-point validation available on generic CI
# runners, where Omarchy itself is not installed.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$ROOT" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1]).resolve()
manifest_path = root / "manifest.json"
with manifest_path.open(encoding="utf-8") as stream:
    manifest = json.load(stream)

required = ("schemaVersion", "id", "name", "version", "author", "license", "description", "kinds", "entryPoints")
missing = [key for key in required if key not in manifest]
if missing:
    raise SystemExit("manifest is missing: " + ", ".join(missing))
if not isinstance(manifest["schemaVersion"], int) or manifest["schemaVersion"] < 1:
    raise SystemExit("manifest schemaVersion must be a positive integer")
for key in ("id", "name", "version", "author", "license", "description"):
    if not isinstance(manifest[key], str) or not manifest[key].strip():
        raise SystemExit(f"manifest {key} must be a non-empty string")
if not isinstance(manifest["kinds"], list) or not manifest["kinds"]:
    raise SystemExit("manifest kinds must be a non-empty list")
if not isinstance(manifest["entryPoints"], dict):
    raise SystemExit("manifest entryPoints must be an object")

for kind, relative in manifest["entryPoints"].items():
    if not isinstance(relative, str) or not relative:
        raise SystemExit(f"entry point {kind} must be a file name")
    path = (root / relative).resolve()
    if root not in path.parents or not path.is_file():
        raise SystemExit(f"entry point {kind} does not point inside the plugin: {relative}")

bar = manifest.get("barWidget")
if "bar-widget" in manifest["kinds"]:
    if not isinstance(bar, dict):
        raise SystemExit("barWidget is required for a bar-widget plugin")
    for key in ("displayName", "description", "category", "defaultSection"):
        if not isinstance(bar.get(key), str) or not bar[key].strip():
            raise SystemExit(f"barWidget {key} must be a non-empty string")
    if bar["defaultSection"] not in ("left", "center", "right"):
        raise SystemExit("barWidget defaultSection must be left, center, or right")

print(f"plugin manifest: PASS ({manifest['id']})")
PY
