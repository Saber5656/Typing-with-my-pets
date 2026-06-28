#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
app="$(./scripts/build.sh)"
launchctl unsetenv TWMP_CODEX_WORKDIR 2>/dev/null || true
if [ "$#" -gt 0 ]; then
  TWMP_CODEX_WORKDIR="$PWD" "$app/Contents/MacOS/TypingWithMyPets" "$@"
else
  TWMP_CODEX_WORKDIR="$PWD" "$app/Contents/MacOS/TypingWithMyPets" >/dev/null 2>&1 &
fi
