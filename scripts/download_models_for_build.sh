#!/bin/bash
# Download ML models before building RPM
# This script should be run before packaging

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
MODELS_DIR="$SCRIPT_DIR/../python/models"

echo "================================"
echo "Downloading ML Models for Nami"
echo "================================"
echo ""

mkdir -p "$MODELS_DIR"

# Download YuNet face detection model
YUNET_URL="https://github.com/opencv/opencv_zoo/raw/main/models/face_detection_yunet/face_detection_yunet_2023mar.onnx"
YUNET_FILE="$MODELS_DIR/face_detection_yunet_2023mar.onnx"

if [ -f "$YUNET_FILE" ]; then
    echo "✓ YuNet model already exists"
else
    echo "Downloading YuNet face detection model..."
    curl -L "$YUNET_URL" -o "$YUNET_FILE"

    # Check file size (should be ~353 KB)
    SIZE=$(stat -f%z "$YUNET_FILE" 2>/dev/null || stat -c%s "$YUNET_FILE" 2>/dev/null)
    if [ $SIZE -lt 300000 ]; then
        echo "✗ YuNet download failed (file too small)"
        rm -f "$YUNET_FILE"
        exit 1
    fi

    echo "✓ YuNet model downloaded successfully ($(du -h "$YUNET_FILE" | cut -f1))"
fi

echo ""

# Download ArcFace recognition model
ARCFACE_URL="https://huggingface.co/garavv/arcface-onnx/resolve/main/arc.onnx?download=true"
ARCFACE_FILE="$MODELS_DIR/arcface_mobilefacenet.onnx"

if [ -f "$ARCFACE_FILE" ]; then
    echo "✓ ArcFace model already exists"
else
    echo "Downloading ArcFace recognition model from Hugging Face..."
    curl -L "$ARCFACE_URL" -o "$ARCFACE_FILE"

    # Check file size (should be ~4-5 MB)
    SIZE=$(stat -f%z "$ARCFACE_FILE" 2>/dev/null || stat -c%s "$ARCFACE_FILE" 2>/dev/null)
    if [ $SIZE -lt 1000000 ]; then
        echo "✗ ArcFace download failed (file too small)"
        rm -f "$ARCFACE_FILE"
        exit 1
    fi

    echo "✓ ArcFace model downloaded successfully ($(du -h "$ARCFACE_FILE" | cut -f1))"
fi

echo ""
echo "================================"
echo "Model Status:"
echo "  YuNet:   $([ -f "$YUNET_FILE" ] && echo "✓ Ready" || echo "✗ Missing")"
echo "  ArcFace: $([ -f "$ARCFACE_FILE" ] && echo "✓ Ready" || echo "✗ Missing")"
echo "================================"
echo ""

if [ -f "$YUNET_FILE" ] && [ -f "$ARCFACE_FILE" ]; then
    echo "✓ All models ready for build!"
    exit 0
else
    echo "⚠️  Some models are missing"
    echo "   App will show download page on first launch"
    exit 0
fi
