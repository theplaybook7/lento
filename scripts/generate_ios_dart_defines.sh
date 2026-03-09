#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
KEYS_FILE_LOCAL="$ROOT_DIR/firebase_keys.local.json"
KEYS_FILE_EXAMPLE="$ROOT_DIR/firebase_keys.example.json"
OUT_FILE="$ROOT_DIR/ios/Flutter/ApiKeys.local.xcconfig"
KEYS_FILE=""

validate_key_file() {
    local file="$1"
    python3 - "$file" <<'PY'
import json
import sys

path = sys.argv[1]
required = ["FIREBASE_IOS_API_KEY"]

with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)

for key in required:
        value = str(data.get(key, "")).strip()
        if not value:
                raise SystemExit(1)
        if value.startswith("REPLACE_WITH_ROTATED_"):
                raise SystemExit(1)
        if not value.startswith("AIza"):
                raise SystemExit(1)
PY
}

if [[ -f "$KEYS_FILE_LOCAL" ]] && validate_key_file "$KEYS_FILE_LOCAL"; then
    KEYS_FILE="$KEYS_FILE_LOCAL"
elif [[ -f "$KEYS_FILE_EXAMPLE" ]] && validate_key_file "$KEYS_FILE_EXAMPLE"; then
    KEYS_FILE="$KEYS_FILE_EXAMPLE"
    echo "Using firebase_keys.example.json because local key file is missing/invalid."
else
    echo "No valid Firebase key file found."
    echo "Checked:"
    echo "- $KEYS_FILE_LOCAL"
    echo "- $KEYS_FILE_EXAMPLE"
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
