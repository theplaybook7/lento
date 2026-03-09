#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
KEYS_FILE_LOCAL="$ROOT_DIR/firebase_keys.local.json"
KEYS_FILE_EXAMPLE="$ROOT_DIR/firebase_keys.example.json"
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

python3 - "$KEYS_FILE" <<'PY'
import json
import sys

path = sys.argv[1]
required = [
  "FIREBASE_IOS_API_KEY",
]

with open(path, "r", encoding="utf-8") as f:
  data = json.load(f)

for key in required:
  value = str(data.get(key, "")).strip()
  if not value:
    raise SystemExit(f"Missing {key} in {path}")
  if value.startswith("REPLACE_WITH_ROTATED_"):
    raise SystemExit(f"Placeholder detected for {key} in {path}")
  if not value.startswith("AIza"):
    raise SystemExit(f"Invalid format for {key} in {path}. Expected Google API key starting with AIza")

print("Firebase key file validation passed.")
PY

cd "$ROOT_DIR"

flutter run -d "iPhone 15 Pro Max" --dart-define-from-file="$KEYS_FILE"
