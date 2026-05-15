#!/usr/bin/env bash
set -euo pipefail

if ! command -v dot >/dev/null 2>&1; then
  echo "error: graphviz 'dot' not found in PATH" >&2
  exit 1
fi

cd "$(dirname "$0")/.."

for f in docs/diagrams/*.dot; do
  out="${f%.dot}.svg"
  echo "render $f -> $out"
  dot -Tsvg "$f" -o "$out"
done
