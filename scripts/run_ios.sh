#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
KEYS_FILE="$ROOT_DIR/firebase_keys.local.json"

if [[ ! -f "$KEYS_FILE" ]]; then
  echo "Missing $KEYS_FILE"
  echo "Create it from firebase_keys.example.json and add your rotated keys."
  exit 1
fi

python3 - "$KEYS_FILE" <<'PY'
import json
import sys

path = sys.argv[1]
required = [
  "FIREBASE_WEB_API_KEY",
  "FIREBASE_IOS_API_KEY",
  "FIREBASE_MACOS_API_KEY",
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
