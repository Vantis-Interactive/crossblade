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

echo "== build place (rojo)"
mkdir -p build
rojo build -o build/crossblade.rbxl

echo "== verify place structure (lune)"
lune run scripts/verify-place build/crossblade.rbxl

echo "ALL CHECKS PASSED"
