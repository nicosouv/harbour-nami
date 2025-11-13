#!/bin/bash
# Download OpenCV pre-built binaries for Sailfish OS build
# This script is used during CI/CD build

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR="$SCRIPT_DIR/.."
OPENCV_DIR="$ROOT_DIR/3rdparty/opencv"

echo "================================"
echo "Downloading OpenCV for Build"
echo "================================"
echo ""

# Create directory
mkdir -p "$OPENCV_DIR"

# For CI build, we'll use OpenCV from system at runtime
# But we need headers and libs for building
# Download OpenCV 4.5.5 headers (lightweight)
echo "Downloading OpenCV headers..."
curl -L "https://github.com/opencv/opencv/archive/refs/tags/4.5.5.tar.gz" -o /tmp/opencv.tar.gz

echo "Extracting headers..."
tar -xzf /tmp/opencv.tar.gz -C /tmp

# Set up OpenCV 4 style include directory structure
mkdir -p "$OPENCV_DIR/include/opencv4/opencv2"

# Copy module headers
cp -r /tmp/opencv-4.5.5/modules/core/include/opencv2/* "$OPENCV_DIR/include/opencv4/opencv2/" 2>/dev/null || true
cp -r /tmp/opencv-4.5.5/modules/imgproc/include/opencv2/* "$OPENCV_DIR/include/opencv4/opencv2/" 2>/dev/null || true
cp -r /tmp/opencv-4.5.5/modules/dnn/include/opencv2/* "$OPENCV_DIR/include/opencv4/opencv2/" 2>/dev/null || true
cp -r /tmp/opencv-4.5.5/modules/imgcodecs/include/opencv2/* "$OPENCV_DIR/include/opencv4/opencv2/" 2>/dev/null || true
cp -r /tmp/opencv-4.5.5/modules/features2d/include/opencv2/* "$OPENCV_DIR/include/opencv4/opencv2/" 2>/dev/null || true

# Copy main headers
cp /tmp/opencv-4.5.5/modules/core/include/opencv2/opencv.hpp "$OPENCV_DIR/include/opencv4/opencv2/" 2>/dev/null || true
cp /tmp/opencv-4.5.5/modules/core/include/opencv2/core.hpp "$OPENCV_DIR/include/opencv4/opencv2/" 2>/dev/null || true

# Create opencv2/opencv.hpp wrapper if it doesn't exist
if [ ! -f "$OPENCV_DIR/include/opencv4/opencv2/opencv.hpp" ]; then
    cat > "$OPENCV_DIR/include/opencv4/opencv2/opencv.hpp" << 'EOFCPP'
#ifndef OPENCV_ALL_HPP
#define OPENCV_ALL_HPP

#include "opencv2/core.hpp"
#include "opencv2/imgproc.hpp"
#include "opencv2/dnn.hpp"

#endif
EOFCPP
fi

# Create opencv_modules.hpp stub (generated file)
cat > "$OPENCV_DIR/include/opencv4/opencv2/opencv_modules.hpp" << 'EOFCPP'
#ifndef OPENCV_MODULES_HPP
#define OPENCV_MODULES_HPP

#define HAVE_OPENCV_CORE
#define HAVE_OPENCV_IMGPROC
#define HAVE_OPENCV_DNN

#endif
EOFCPP

# Cleanup
rm -rf /tmp/opencv.tar.gz /tmp/opencv-4.5.5

echo ""
echo "✓ OpenCV headers downloaded"
echo ""
