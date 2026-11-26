#!/usr/bin/env bash
# Full local verification pipeline. Mirrors .github/workflows/ci.yml.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== format (stylua --check)"
stylua --check src tests scripts

echo "== lint (selene)"
selene src
(cd tests && selene .)

echo "== unit + integrity tests (lune)"
lune run tests/run

echo "== build places (rojo)"
mkdir -p build
rojo build -o build/crossblade.rbxl
for place in hub ffa tdm duel1v1 duel2v2; do
	rojo build "places/$place.project.json" -o "build/$place.rbxl"
done

echo "== verify place structure (lune)"
lune run scripts/verify-place build/crossblade.rbxl
lune run scripts/verify-place build/hub.rbxl Hub Lobby
lune run scripts/verify-place build/ffa.rbxl Arena FreeForAll
lune run scripts/verify-place build/tdm.rbxl Arena TeamDeathmatch
lune run scripts/verify-place build/duel1v1.rbxl Arena CasualDuel1v1
lune run scripts/verify-place build/duel2v2.rbxl Arena CasualDuelTeam

echo "ALL CHECKS PASSED"
