#!/bin/bash
# Download ML models before building RPM
# This script should be run before packaging
#
# Both models come from the official OpenCV Zoo and are verified against
# pinned SHA256 checksums (supply chain integrity).

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
MODELS_DIR="$SCRIPT_DIR/../python/models"

YUNET_URL="https://media.githubusercontent.com/media/opencv/opencv_zoo/main/models/face_detection_yunet/face_detection_yunet_2023mar.onnx"
YUNET_FILE="$MODELS_DIR/face_detection_yunet_2023mar.onnx"
YUNET_SHA256="8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4"

SFACE_URL="https://media.githubusercontent.com/media/opencv/opencv_zoo/main/models/face_recognition_sface/face_recognition_sface_2021dec.onnx"
SFACE_FILE="$MODELS_DIR/face_recognition_sface_2021dec.onnx"
SFACE_SHA256="0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79"

echo "================================"
echo "Downloading ML Models for Nami"
echo "================================"
echo ""

mkdir -p "$MODELS_DIR"

sha256_of() {
    sha256sum "$1" 2>/dev/null | cut -d' ' -f1 || shasum -a 256 "$1" | cut -d' ' -f1
}

download_and_verify() {
    local name="$1" url="$2" file="$3" expected="$4"

    if [ -f "$file" ] && [ "$(sha256_of "$file")" = "$expected" ]; then
        echo "✓ $name model already present and verified"
        return 0
    fi

    echo "Downloading $name model..."
    curl -fL -H "User-Agent: Mozilla/5.0" "$url" -o "$file"

    local actual
    actual="$(sha256_of "$file")"
    if [ "$actual" != "$expected" ]; then
        echo "✗ $name checksum mismatch!"
        echo "  expected: $expected"
        echo "  actual:   $actual"
        rm -f "$file"
        exit 1
    fi

    echo "✓ $name model downloaded and verified ($(du -h "$file" | cut -f1))"
}

download_and_verify "YuNet" "$YUNET_URL" "$YUNET_FILE" "$YUNET_SHA256"
echo ""
download_and_verify "SFace" "$SFACE_URL" "$SFACE_FILE" "$SFACE_SHA256"

# Drop the previously bundled unofficial ArcFace model if present
rm -f "$MODELS_DIR/arcface_mobilefacenet.onnx"

echo ""
echo "================================"
echo "✓ All models ready for build!"
echo "================================"
