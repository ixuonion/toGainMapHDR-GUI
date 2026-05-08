#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

required_files=(
  "$ROOT_DIR/toGainMapHDR"
  "$ROOT_DIR/GainMapKernel.ci.metallib"
  "$ROOT_DIR/RGBGainMapKernel.ci.metallib"
  "$ROOT_DIR/Vendor/toGainMapHDR/main.swift"
  "$ROOT_DIR/Vendor/toGainMapHDR/CustomFilter/GainMapFilter.swift"
  "$ROOT_DIR/Vendor/toGainMapHDR/CustomFilter/RGBGainMapFilter.swift"
)

for file in "${required_files[@]}"; do
  if [[ ! -f "$file" ]]; then
    echo "missing required file: $file" >&2
    exit 1
  fi
done

if [[ ! -x "$ROOT_DIR/toGainMapHDR" ]]; then
  echo "toGainMapHDR is not executable" >&2
  exit 1
fi

help_output="$($ROOT_DIR/toGainMapHDR -help 2>&1 || true)"
for option in "-R <value>" "-H <value>" "-b <base_image>" "-m"; do
  if [[ "$help_output" != *"$option"* ]]; then
    echo "help output does not mention $option" >&2
    exit 1
  fi
done

echo "runtime checks passed"
