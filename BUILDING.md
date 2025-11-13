# Building Harbour Nami

This document explains how to build Harbour Nami for Sailfish OS.

## Prerequisites

### Required Packages

```bash
# On Sailfish SDK Platform
pkcon install opencv-devel
pkcon install qt5-qtdeclarative-devel
pkcon install qt5-qtquick-devel
pkcon install sailfish-components-webview-qt5-devel
```

### ONNX Runtime

ONNX Runtime is **not available** in Sailfish OS repositories and must be bundled with the app.

#### Option A: Use Pre-built Binary (Recommended)

Download pre-compiled ONNX Runtime for ARM:

```bash
# Download ONNX Runtime 1.16.3 for Linux ARM64
wget https://github.com/microsoft/onnxruntime/releases/download/v1.16.3/onnxruntime-linux-aarch64-1.16.3.tgz

# Extract
tar -xzf onnxruntime-linux-aarch64-1.16.3.tgz

# Copy to 3rdparty directory
mkdir -p 3rdparty/onnxruntime
cp -r onnxruntime-linux-aarch64-1.16.3/include 3rdparty/onnxruntime/
cp -r onnxruntime-linux-aarch64-1.16.3/lib 3rdparty/onnxruntime/
```

The library will be bundled in the RPM package.

#### Option B: Compile from Source (Advanced)

If you need to compile ONNX Runtime for ARM yourself:

```bash
git clone --recursive https://github.com/Microsoft/onnxruntime
cd onnxruntime

# For ARM64
./build.sh --config Release --build_shared_lib \
  --parallel --skip_tests \
  --cmake_extra_defines CMAKE_POSITION_INDEPENDENT_CODE=ON

# Output: build/Linux/Release/libonnxruntime.so
```

## Build Steps

### 1. Setup Build Environment

```bash
# Clone repository
git clone https://github.com/nicosouv/harbour-nami
cd harbour-nami

# Download ML models (if not already present)
bash scripts/download_models_for_build.sh
```

### 2. Build with CMake

```bash
mkdir build
cd build

cmake .. \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/usr

make -j$(nproc)
```

### 3. Build RPM Package

Using Sailfish SDK:

```bash
mb2 -t SailfishOS-5.0.0.43-aarch64 build
```

The RPM will be in `RPMS/` directory.

## CI/CD Build

The GitHub Actions workflow automatically:

1. Downloads ML models (YuNet + ArcFace)
2. Downloads ONNX Runtime pre-built binaries
3. Builds for 3 architectures (armv7hl, aarch64, i486)
4. Creates GitHub release with RPM packages

See `.github/workflows/build.yml` for details.

## Dependencies Summary

### Build-time
- CMake >= 3.5
- Qt5 development packages
- OpenCV development packages (opencv-devel)
- Sailfish SDK

### Runtime (bundled in RPM)
- OpenCV >= 4.0 ✅ (available in Sailfish repos)
- Qt5 ✅ (pre-installed on Sailfish OS)
- ONNX Runtime 📦 (bundled with app)
- ML Models 📦 (bundled with app)

### Runtime (from Sailfish repos)
- `sailfishsilica-qt5`
- `opencv`
- `qt5-qtsql-sqlite`

## File Structure

```
harbour-nami/
├── src/                   # C++ source code
│   ├── facedetector.*     # YuNet face detection
│   ├── facerecognizer.*   # ArcFace recognition
│   ├── facedatabase.*     # SQLite database
│   ├── facepipeline.*     # Main pipeline
│   └── main.cpp           # Entry point
├── qml/                   # QML UI
├── python/models/         # ML models (ONNX)
│   ├── face_detection_yunet_2023mar.onnx
│   └── arcface_mobilefacenet.onnx
├── 3rdparty/
│   └── onnxruntime/       # ONNX Runtime library
│       ├── include/
│       └── lib/
├── CMakeLists.txt         # Build configuration
└── rpm/
    └── harbour-nami.yaml  # RPM spec
```

## Troubleshooting

### Missing ONNX Runtime

```
Error: libonnxruntime.so not found
```

Solution: Download pre-built ONNX Runtime (see Option A above).

### OpenCV Not Found

```
CMake Error: Could not find OpenCV
```

Solution:
```bash
pkcon install opencv-devel
```

### Build Fails in Sailfish SDK

Make sure you're using the correct target:

```bash
# List available targets
sdk-assistant list

# Use correct target for your device
mb2 -t SailfishOS-5.0.0.43-aarch64 build
```

## Performance Notes

Expected performance on Sailfish OS devices:

- **Sony Xperia 10 III**: 15-20 FPS detection, 50-80ms recognition
- **Sony Xperia XA2**: 20-25 FPS detection, 80-120ms recognition
- **Jolla C2**: 10-15 FPS detection, 150-200ms recognition

The C++ implementation is 2-5x faster than Python version.
