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

    echo "✓ YuNet model downloaded successfully"
fi

echo ""

# Download/prepare ArcFace model
ARCFACE_FILE="$MODELS_DIR/arcface_mobilefacenet.onnx"

if [ -f "$ARCFACE_FILE" ]; then
    echo "✓ ArcFace model already exists"
else
    echo "⚠️  ArcFace model not found"
    echo ""
    echo "Please provide ArcFace MobileFaceNet ONNX model."
    echo ""
    echo "Options:"
    echo "1. Download from InsightFace:"
    echo "   https://github.com/deepinsight/insightface/tree/master/model_zoo"
    echo ""
    echo "2. Use a pre-converted model:"
    echo "   - Place your arcface_mobilefacenet.onnx in python/models/"
    echo ""
    echo "3. Convert from PyTorch (if you have the weights):"
    echo "   - Run the conversion script in python/models/"
    echo ""
    echo "Expected location: $ARCFACE_FILE"
    echo ""

    # Check if user wants to continue without ArcFace
    read -p "Continue without ArcFace model? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
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
