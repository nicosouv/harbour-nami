# Installation Instructions for Harbour Nami

## Prerequisites

### ML Models

Download the required machine learning models before building:

```bash
cd python
python3 download_models.py
```

**Required models:**

1. **YuNet Face Detection** (~353 KB)
   - Download from: https://github.com/opencv/opencv_zoo/raw/main/models/face_detection_yunet/face_detection_yunet_2023mar.onnx
   - Place at: `python/models/face_detection_yunet_2023mar.onnx`

2. **ArcFace Recognition** (~2-5 MB for MobileFaceNet)
   - See `python/models/README.md` for download options
   - Recommended: InsightFace buffalo_sc model
   - Place at: `python/models/arcface_mobilefacenet.onnx`

### Python Dependencies (on device)

Nami requires Python 3 with the following packages on your Sailfish OS device:

```bash
# On Sailfish OS device
devel-su
pkcon install python3-base python3-numpy python3-opencv python3-Pillow pyotherside-qml-plugin-python3-qt5
```

**Note:** Some packages may need to be installed from OpenRepos or compiled manually if not available in official repos.

## Building

### Option 1: Using Sailfish SDK

```bash
# In Sailfish SDK
mb2 -t SailfishOS-5.0.0.43-armv7hl build
mb2 -t SailfishOS-5.0.0.43-aarch64 build
mb2 -t SailfishOS-5.0.0.43-i486 build
```

### Option 2: Using Docker

```bash
docker run --rm \
  -v $(pwd):/home/mersdk/src:z \
  coderus/sailfishos-platform-sdk:5.0.0.43 \
  bash -c "cd /home/mersdk/src && mb2 -t SailfishOS-5.0.0.43-armv7hl build"
```

### Option 3: GitHub Actions

Push a git tag to trigger automatic builds:

```bash
git tag v0.1.0
git push origin v0.1.0
```

Builds will be available as GitHub Release artifacts.

## Installation on Device

### Via RPM

```bash
# Transfer RPM to device
scp RPMS/harbour-nami-*.rpm defaultuser@192.168.x.x:~/

# On device
devel-su
pkcon install-local harbour-nami-*.rpm
```

### Via Harbour Store

Upload the RPM to https://harbour.jolla.com after validation.

## Post-Installation

### First Launch

1. Open Nami
2. Grant camera and storage permissions
3. Pull down menu → "Scan Gallery"
4. Wait for face detection to complete
5. Review unknown faces and identify people

### Model Verification

Check that models are correctly installed:

```bash
# On device
ls -lh /usr/share/harbour-nami/python/models/
```

Should show:
- `face_detection_yunet_2023mar.onnx` (~353 KB)
- `arcface_mobilefacenet.onnx` (~2-5 MB)

## Troubleshooting

### "Python module not found"

Install PyOtherSide:
```bash
devel-su
pkcon install pyotherside-qml-plugin-python3-qt5
```

### "No module named cv2"

Install OpenCV for Python:
```bash
devel-su
pkcon install python3-opencv
```

If not available, compile from source or use OpenRepos.

### "Models not found"

Ensure models are in correct location:
```bash
/usr/share/harbour-nami/python/models/face_detection_yunet_2023mar.onnx
/usr/share/harbour-nami/python/models/arcface_mobilefacenet.onnx
```

### Poor Performance

- Close background apps
- Lower recognition quality in Settings
- Ensure device is not thermally throttling
- Check available RAM (need ~200MB minimum)

### Database Issues

Reset database if corrupted:
```bash
rm ~/.local/share/harbour-nami/database.db
```

Then restart app and re-scan gallery.

## Uninstallation

```bash
devel-su
pkcon remove harbour-nami

# Optionally remove user data
rm -rf ~/.local/share/harbour-nami/
```

## Development Installation

For testing during development:

```bash
# Build in SDK
mb2 build

# Install directly
mb2 deploy --sdk

# Or copy files manually
scp -r qml/ python/ defaultuser@192.168.x.x:/usr/share/harbour-nami/
```

## Supported Devices

Tested on:
- Sony Xperia 10 III (Sailfish 4.5+)
- Sony Xperia 10 II (Sailfish 4.3+)
- Sony Xperia XA2 (Sailfish 4.0+)

Should work on:
- Sony Xperia X
- Jolla Phone (limited performance)
- Jolla C (limited performance)

Minimum requirements:
- Sailfish OS 4.0+
- 2GB RAM
- ARMv7 or ARM64 architecture
- 100MB free storage
