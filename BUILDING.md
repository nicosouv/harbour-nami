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

### Face recognition

Recognition uses OpenCV's built-in `FaceRecognizerSF` (objdetect module) with
the OpenCV Zoo SFace model, downloaded and checksum-verified by
`scripts/download_models_for_build.sh`. No extra runtime is needed.

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
│   └── face_recognition_sface_2021dec.onnx
├── 3rdparty/
│       ├── include/
│       └── lib/
├── CMakeLists.txt         # Build configuration
└── rpm/
    └── harbour-nami.yaml  # RPM spec
```

## Troubleshooting

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
