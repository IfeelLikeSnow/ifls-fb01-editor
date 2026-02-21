#!/usr/bin/env bash
set -euo pipefail
VER="${1:-}"
if [[ -z "$VER" ]]; then
  echo "usage: tools/build_release_zip.sh X.Y.Z"
  exit 2
fi
mkdir -p dist
( cd reaper && zip -r "../dist/ifls-fb01-editor_${VER}.zip" . )
echo "dist/ifls-fb01-editor_${VER}.zip"
