#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME="LED'oh!"
PLATFORM="tg5040"
BINARY="ports/${PLATFORM}/pak/bin/ledoh"

echo ""
echo "=== Building ${APP_NAME} for ${PLATFORM} ==="
echo ""

docker run --rm \
    -v "$PROJECT_DIR":/workspace \
    ghcr.io/loveretro/tg5040-toolchain \
    make -C /workspace/ports/${PLATFORM} -f Makefile

echo ""
echo "=== Build for ${PLATFORM} complete ==="
echo "Binary: ${BINARY}"
echo ""
