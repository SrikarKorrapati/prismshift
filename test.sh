#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
mkdir -p work .build/ModuleCache

if [[ "${1:-}" == "--media" ]]; then
  command -v ffmpeg >/dev/null || { echo 'FFmpeg is required only to generate the media test fixture.' >&2; exit 1; }
  mkdir -p work/media-fixtures
  ffmpeg -nostdin -hide_banner -loglevel error -y \
    -f lavfi -i color=c=orange:s=128x96:d=0.5 \
    -f lavfi -i sine=frequency=440:duration=0.5 \
    -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest \
    work/media-fixtures/Sample.mov
elif [[ $# -gt 0 ]]; then
  echo 'Usage: ./test.sh [--media]' >&2
  exit 1
fi

swiftc -parse-as-library -swift-version 5 \
  -module-cache-path "$ROOT/.build/ModuleCache" \
  -target "$(uname -m)-apple-macos14.0" \
  Sources/PrismShift/FileAction.swift \
  Sources/PrismShift/FileInspector.swift \
  Sources/PrismShift/ConversionService.swift \
  Sources/PrismShift/GlassWheelView.swift \
  Sources/PrismShift/DragGestureGate.swift \
  Tests/ConversionSmokeTests.swift \
  -o work/conversion-smoke-tests \
  -framework AppKit -framework SwiftUI -framework AVFoundation \
  -framework ImageIO -framework PDFKit

./work/conversion-smoke-tests
