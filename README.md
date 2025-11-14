# Harbour Nami

Face recognition photo gallery for Sailfish OS.

## Features

- **Privacy First**: All face recognition processing happens locally on your device
- **Smart Organization**: Automatically group photos by detected faces
- **Face Tagging**: Name detected faces for easy identification
- **Gallery Integration**: Seamlessly works with your existing photo gallery
- **Performance Optimized**: Target 30+ FPS for smooth operation

## Building

### Requirements

- Sailfish SDK (for CI/CD builds)
- Docker (recommended)
- ML Models (YuNet + ArcFace)

### Architecture

This app uses **C++ native implementation** with:
- **OpenCV minimal** (core, imgproc, dnn modules only) - bundled
- **ONNX Runtime** - bundled
- **CMake** build system
- Target: Jolla C2 (aarch64)

### CI/CD Build (Recommended)

The app is designed for **CI/CD only builds** using GitHub Actions:

1. Push a tag: `git tag v0.2.0 && git push origin v0.2.0`
2. GitHub Actions will:
   - Cross-compile OpenCV minimal (cached)
   - Download ONNX Runtime
   - Download ML models
   - Build the RPM
   - Create a GitHub release

### Manual Build (Advanced)

If you need to build locally:

```bash
# 1. Download ML models
./scripts/download_models_for_build.sh

# 2. Build OpenCV minimal (inside Sailfish SDK container)
docker run --rm \
  -v $(pwd):/home/mersdk/src:z \
  coderus/sailfishos-platform-sdk:5.0.0.43 \
  bash -c "cd /home/mersdk/src && sb2 -t SailfishOS-5.0.0.43-aarch64 bash scripts/build_opencv_minimal.sh"

# 3. Download ONNX Runtime
./scripts/download_onnxruntime.sh

# 4. Build the app
docker run --rm \
  -v $(pwd):/home/mersdk/src:z \
  coderus/sailfishos-platform-sdk:5.0.0.43 \
  bash -c "cd /home/mersdk/src && mb2 -t SailfishOS-5.0.0.43-aarch64 build"
```

## Installation

Download the RPM from [GitHub Releases](https://github.com/nicosouv/harbour-nami/releases) or OpenRepos, then install:

```bash
pkcon install-local harbour-nami-*.rpm
```

## Development Status

This is an early development version. Core features are being implemented.

### Roadmap

- [x] Basic UI with Silica components
- [x] Settings page
- [ ] Gallery access and permissions
- [ ] Face detection engine
- [ ] Face recognition ML model
- [ ] Face grouping system
- [ ] Face naming dialog
- [ ] Contact integration

## License

See LICENSE file for details.

## Contributing

Contributions are welcome! Please feel free to submit issues and pull requests.
