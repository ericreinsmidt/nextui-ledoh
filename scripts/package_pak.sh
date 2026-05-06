#!/bin/bash
# Package LED'oh! .pak for distribution
set -e
cd "$(dirname "$0")/.."

PAK_NAME="LED'oh!.pak"
DIST_DIR="dist"
STAGE_DIR="$DIST_DIR/$PAK_NAME"

# Read version from pak.json
VERSION=$(grep '"version"' pak.json | head -1 | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/')
if [ -z "$VERSION" ]; then
    echo "ERROR: Could not read version from pak.json"
    exit 1
fi
echo "=== Packaging LED'oh! ${VERSION} ==="

# Check binary exists
if [ ! -f ports/tg5040/pak/bin/ledoh ]; then
    echo "ERROR: Binary not found. Run 'make build' first."
    exit 1
fi

# Clean and stage
rm -rf "$DIST_DIR"
mkdir -p "$STAGE_DIR/bin"
mkdir -p "$STAGE_DIR/res"

# Copy files
cp ports/tg5040/pak/launch.sh "$STAGE_DIR/"
cp ports/tg5040/pak/pak.json "$STAGE_DIR/"
cp ports/tg5040/pak/bin/ledoh "$STAGE_DIR/bin/"
cp ports/tg5040/pak/res/front.png "$STAGE_DIR/res/"
cp ports/tg5040/pak/res/back.png "$STAGE_DIR/res/"
cp ports/tg5040/pak/res/font.ttf "$STAGE_DIR/res/"

# Copy splash if it exists
if [ -f ports/tg5040/pak/res/splash.png ]; then
    cp ports/tg5040/pak/res/splash.png "$STAGE_DIR/res/"
fi

# Create zip
ZIP_NAME="LED'oh!.tg5040.pak.zip"
cd "$DIST_DIR"
zip -r "$ZIP_NAME" "$PAK_NAME"
cd ..

echo "=== Package created: $DIST_DIR/$ZIP_NAME ==="
