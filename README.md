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

- Sailfish SDK
- Qt 5.6+
- QtMultimedia

### Build with mb2

```bash
mb2 -t SailfishOS-5.0.0.43-armv7hl build
```

### Build with Docker

```bash
docker run --rm \
  -v $(pwd):/home/mersdk/src:z \
  coderus/sailfishos-platform-sdk:5.0.0.43 \
  bash -c "cd /home/mersdk/src && mb2 -t SailfishOS-5.0.0.43-armv7hl build"
```

## Installation

Install the RPM package on your Sailfish OS device:

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
