#!/bin/bash
# Cross-compile minimal OpenCV for Sailfish OS (aarch64)
# Builds only: core, imgproc, dnn modules
# Target: Jolla C2 (aarch64)

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR="$SCRIPT_DIR/.."
BUILD_DIR="$ROOT_DIR/build-opencv"
INSTALL_DIR="$ROOT_DIR/3rdparty/opencv"
OPENCV_VERSION="4.5.5"

echo "========================================"
echo "Building OpenCV Minimal for Sailfish OS"
echo "========================================"
echo "Version: $OPENCV_VERSION"
echo "Target: aarch64 (Jolla C2)"
echo "Modules: core, imgproc, dnn"
echo ""

# Clean previous builds
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Clean and recreate install directory
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"

# Download OpenCV if not cached
if [ ! -f "/tmp/opencv-${OPENCV_VERSION}.tar.gz" ]; then
    echo "Downloading OpenCV ${OPENCV_VERSION}..."
    curl -L "https://github.com/opencv/opencv/archive/refs/tags/${OPENCV_VERSION}.tar.gz" \
         -o "/tmp/opencv-${OPENCV_VERSION}.tar.gz"
fi

echo "Extracting OpenCV..."
tar -xzf "/tmp/opencv-${OPENCV_VERSION}.tar.gz" -C "$BUILD_DIR"

cd "$BUILD_DIR/opencv-${OPENCV_VERSION}"

echo ""
echo "Configuring OpenCV minimal build..."
echo "Building for aarch64 cross-compilation"
echo ""

# When called via "sb2 -t target bash script.sh", we're already in sb2
# Just use cmake and make directly (sb2 wraps them automatically)
CMAKE_CMD="cmake"
MAKE_CMD="make"

mkdir -p build
cd build

# Configure with minimal modules
$CMAKE_CMD \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" \
    -DBUILD_SHARED_LIBS=ON \
    \
    `# Minimal module selection` \
    -DBUILD_LIST=core,imgproc,dnn \
    \
    `# Disable everything else` \
    -DBUILD_opencv_apps=OFF \
    -DBUILD_opencv_java=OFF \
    -DBUILD_opencv_python2=OFF \
    -DBUILD_opencv_python3=OFF \
    -DBUILD_EXAMPLES=OFF \
    -DBUILD_DOCS=OFF \
    -DBUILD_TESTS=OFF \
    -DBUILD_PERF_TESTS=OFF \
    -DBUILD_JAVA=OFF \
    -DBUILD_FAT_JAVA_LIB=OFF \
    \
    `# Disable GUI and media I/O` \
    -DWITH_GTK=OFF \
    -DWITH_QT=OFF \
    -DWITH_WIN32UI=OFF \
    -DWITH_FFMPEG=OFF \
    -DWITH_GSTREAMER=OFF \
    -DWITH_V4L=OFF \
    -DWITH_1394=OFF \
    -DWITH_JPEG=OFF \
    -DWITH_PNG=OFF \
    -DWITH_TIFF=OFF \
    -DWITH_WEBP=OFF \
    -DWITH_JASPER=OFF \
    -DWITH_OPENEXR=OFF \
    \
    `# Disable CUDA, OpenCL, etc` \
    -DWITH_CUDA=OFF \
    -DWITH_OPENCL=OFF \
    -DWITH_IPP=OFF \
    -DWITH_TBB=OFF \
    -DWITH_EIGEN=OFF \
    -DWITH_LAPACK=OFF \
    \
    `# Enable only essential features for DNN` \
    -DWITH_PROTOBUF=ON \
    -DBUILD_PROTOBUF=ON \
    -DOPENCV_DNN_OPENCL=OFF \
    -DOPENCV_DNN_CUDA=OFF \
    \
    `# ARM optimizations for aarch64` \
    -DENABLE_NEON=ON \
    -DCPU_BASELINE=NEON \
    \
    `# Installation` \
    -DCMAKE_INSTALL_LIBDIR=lib \
    ..

echo ""
echo "Building OpenCV (this may take 10-30 minutes)..."
echo ""

# Build with all available cores
$MAKE_CMD -j$(nproc)

echo ""
echo "Installing to $INSTALL_DIR..."
echo ""

$MAKE_CMD install

echo ""
echo "Build summary:"
echo "=============="
ls -lh "$INSTALL_DIR/lib"/libopencv_*.so* || true

# Calculate total size
TOTAL_SIZE=$(du -sh "$INSTALL_DIR/lib" | cut -f1)
echo ""
echo "Total library size: $TOTAL_SIZE"
echo ""
echo "✓ OpenCV minimal build complete!"
echo ""
echo "Installed to: $INSTALL_DIR"
echo "Modules: core, imgproc, dnn"
echo ""
