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
rm -rf "$INSTALL_DIR"
mkdir -p "$BUILD_DIR"
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

# Detect if running in Sailfish OS SDK (scratchbox2)
if command -v sb2 &> /dev/null; then
    echo "Detected Sailfish OS SDK environment"
    USE_SB2=true

    # Get toolchain info from sb2
    SB2_TARGET=$(sb2-config -l | grep default | awk '{print $1}')
    echo "SB2 Target: $SB2_TARGET"

    # Toolchain paths
    TOOLCHAIN_FILE="$BUILD_DIR/sailfish-toolchain.cmake"

    # Create CMake toolchain file for SailfishOS
    cat > "$TOOLCHAIN_FILE" << 'EOF'
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)

# Use sb2 for cross-compilation
set(CMAKE_C_COMPILER gcc)
set(CMAKE_CXX_COMPILER g++)

# SailfishOS sysroot (will be set by sb2)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# Flags for ARM optimization
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -march=armv8-a -mtune=cortex-a53")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -march=armv8-a -mtune=cortex-a53")
EOF

    CMAKE_CMD="sb2 cmake"
    MAKE_CMD="sb2 make"
else
    echo "WARNING: Not in Sailfish OS SDK - building for host architecture"
    echo "This is OK for CI with Docker, but won't work for local builds"
    USE_SB2=false
    TOOLCHAIN_FILE=""
    CMAKE_CMD="cmake"
    MAKE_CMD="make"
fi

echo ""
echo "Configuring OpenCV minimal build..."
echo ""

mkdir -p build
cd build

# Configure with minimal modules
$CMAKE_CMD \
    ${TOOLCHAIN_FILE:+-DCMAKE_TOOLCHAIN_FILE=$TOOLCHAIN_FILE} \
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
    `# ARM optimizations` \
    -DENABLE_NEON=ON \
    -DCPU_BASELINE=NEON \
    -DENABLE_VFPV3=ON \
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
