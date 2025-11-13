#!/bin/bash
# Download ONNX Runtime pre-built binaries for ARM
# This script is used during CI/CD build

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR="$SCRIPT_DIR/.."
ONNX_DIR="$ROOT_DIR/3rdparty/onnxruntime"

echo "================================"
echo "Downloading ONNX Runtime for ARM"
echo "================================"
echo ""

# ONNX Runtime version
VERSION="1.16.3"

# Detect architecture
ARCH=$(uname -m)
if [ "$ARCH" = "aarch64" ]; then
    PLATFORM="linux-aarch64"
elif [ "$ARCH" = "armv7l" ]; then
    PLATFORM="linux-armhf"
elif [ "$ARCH" = "x86_64" ]; then
    # For local dev/testing
    PLATFORM="linux-x64"
else
    echo "Unsupported architecture: $ARCH"
    exit 1
fi

FILENAME="onnxruntime-$PLATFORM-$VERSION.tgz"
URL="https://github.com/microsoft/onnxruntime/releases/download/v$VERSION/$FILENAME"

echo "Platform: $PLATFORM"
echo "Version: $VERSION"
echo "URL: $URL"
echo ""

# Create directories
mkdir -p "$ONNX_DIR"
mkdir -p "$ROOT_DIR/tmp"

# Download if not already present
if [ -f "$ONNX_DIR/lib/libonnxruntime.so" ]; then
    echo "✓ ONNX Runtime already present"
    exit 0
fi

echo "Downloading ONNX Runtime..."
cd "$ROOT_DIR/tmp"
curl -L "$URL" -o "$FILENAME"

echo "Extracting..."
tar -xzf "$FILENAME"

# Find extracted directory
EXTRACTED_DIR=$(find . -maxdepth 1 -type d -name "onnxruntime-*" | head -n 1)

if [ -z "$EXTRACTED_DIR" ]; then
    echo "✗ Failed to find extracted directory"
    exit 1
fi

echo "Copying to 3rdparty/onnxruntime..."
cp -r "$EXTRACTED_DIR/include" "$ONNX_DIR/"
cp -r "$EXTRACTED_DIR/lib" "$ONNX_DIR/"

# Verify
if [ -f "$ONNX_DIR/lib/libonnxruntime.so" ]; then
    echo "✓ ONNX Runtime installed successfully"
    echo "  Library: $(du -h "$ONNX_DIR/lib/libonnxruntime.so" | cut -f1)"
else
    echo "✗ Failed to install ONNX Runtime"
    exit 1
fi

# Cleanup
rm -rf "$ROOT_DIR/tmp/$FILENAME"
rm -rf "$ROOT_DIR/tmp/$EXTRACTED_DIR"

echo ""
echo "================================"
echo "ONNX Runtime Status:"
echo "  Include: $([ -d "$ONNX_DIR/include" ] && echo "✓ Ready" || echo "✗ Missing")"
echo "  Library: $([ -f "$ONNX_DIR/lib/libonnxruntime.so" ] && echo "✓ Ready" || echo "✗ Missing")"
echo "================================"
echo ""
