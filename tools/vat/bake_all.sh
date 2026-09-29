#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BLENDER="${BLENDER:-blender}"
if (( $# == 0 )); then
  set -- robot_grunt robot_runner robot_spitter robot_tank robot_boss alien_grunt alien_runner alien_spitter alien_tank alien_boss
fi
for monster in "$@"; do
  "$BLENDER" -b -P "$ROOT/tools/vat/bake_vat.py" -- "$monster"
done
