#!/bin/bash
# Script to install OpenCV libraries on Sailfish OS device
# Run this on your Jolla C2 as root (devel-su)

set -e

echo "=== Installing OpenCV for harbour-nami ==="

# Download pre-built OpenCV libraries for ARM64 Linux
# Using Alpine Linux packages (musl-based but should work)
OPENCV_VERSION="4.8.1-r0"

cd /tmp

# Download OpenCV core packages from Alpine Linux (aarch64)
echo "Downloading OpenCV libraries..."
curl -L "https://dl-cdn.alpinelinux.org/alpine/v3.19/community/aarch64/opencv-4.8.1-r0.apk" -o opencv.apk
curl -L "https://dl-cdn.alpinelinux.org/alpine/v3.19/community/aarch64/opencv-dev-4.8.1-r0.apk" -o opencv-dev.apk

# Extract .apk files (they are just tar.gz)
echo "Extracting libraries..."
mkdir -p opencv-extract
cd opencv-extract
tar -xzf ../opencv.apk
tar -xzf ../opencv-dev.apk

# Install libraries to /usr/lib64
echo "Installing to /usr/lib64..."
cp -v usr/lib/*.so.* /usr/lib64/ || true
cp -v usr/lib/*.so /usr/lib64/ || true

# Create necessary symlinks
cd /usr/lib64
ln -sf libopencv_core.so.408 libopencv_core.so || true
ln -sf libopencv_imgproc.so.408 libopencv_imgproc.so || true
ln -sf libopencv_dnn.so.408 libopencv_dnn.so || true

echo "✓ OpenCV libraries installed"
echo ""
echo "Installed libraries:"
ls -lh /usr/lib64/libopencv*.so*

# Cleanup
cd /tmp
rm -rf opencv.apk opencv-dev.apk opencv-extract

echo ""
echo "✓ Installation complete!"
echo "You can now run harbour-nami"
