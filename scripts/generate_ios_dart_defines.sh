#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
KEYS_FILE="$ROOT_DIR/firebase_keys.local.json"
OUT_FILE="$ROOT_DIR/ios/Flutter/ApiKeys.local.xcconfig"

if [[ ! -f "$KEYS_FILE" ]]; then
    echo "Missing $KEYS_FILE"
    echo "Create it from firebase_keys.example.json and add your rotated keys."
    exit 1
fi

python3 - "$KEYS_FILE" "$OUT_FILE" <<'PY'
import base64
import json
import pathlib
import sys

keys_path = sys.argv[1]
out_path = pathlib.Path(sys.argv[2])

with open(keys_path, "r", encoding="utf-8") as f:
    data = json.load(f)

required = [
    "FIREBASE_IOS_API_KEY",
]

pairs = []
for key in required:
    value = str(data.get(key, "")).strip()
    if not value:
        raise SystemExit(f"Missing {key} in {keys_path}")
    if value.startswith("REPLACE_WITH_ROTATED_"):
        raise SystemExit(f"Placeholder detected for {key} in {keys_path}")
    if not value.startswith("AIza"):
        raise SystemExit(f"Invalid format for {key} in {keys_path}. Expected a Google API key starting with AIza")
    pairs.append(f"{key}={value}")

encoded = ",".join(base64.b64encode(item.encode("utf-8")).decode("utf-8") for item in pairs)
out_path.write_text(
    "// Generated from firebase_keys.local.json. Do not commit this file.\n"
    f"DART_DEFINES={encoded}\n",
    encoding="utf-8",
)

print(f"Generated {out_path}")
PY
