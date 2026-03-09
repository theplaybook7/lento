#!/usr/bin/env bash
set -euo pipefail

KEYS_FILE="firebase_keys.local.json"

if [[ ! -f "$KEYS_FILE" ]]; then
  echo "Missing $KEYS_FILE"
  echo "Create it from firebase_keys.example.json and add your rotated keys."
  exit 1
fi

flutter run -d macos --dart-define-from-file="$KEYS_FILE"
