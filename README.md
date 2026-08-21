# Harbour Nami

Face recognition photo gallery for Sailfish OS. Everything runs on the device:
no cloud, no account, no network access at any point.

## Features

- **Privacy first**: face detection and recognition run locally, and the app
  never needs an internet connection
- **People**: photos grouped automatically by detected face, named once and
  recognised from then on, with suggestions while you identify
- **Contacts**: link a person to an entry in your address book, or keep them
  in the app only
- **Events**: photos grouped by day, several days combined into a named trip,
  with a schematic offline route map
- **Memories**: photos from around today's date in previous years, plus a
  year-by-year recap
- **Sharing**: send photos to any target the system offers, from a photo, a
  person, a day, a trip or a memory
- **Encrypted backup**: export everything you have identified, protected by a
  passphrase you choose, and restore it on another device
- **GDPR**: full data export and one-tap deletion of everything the app stores
- **Multilingual**: English, French, German, Italian, Spanish, Finnish and
  Norwegian, with an in-app language override

## Installation

Download the RPM for your architecture from
[GitHub Releases](https://github.com/nicosouv/harbour-nami/releases), then:

```bash
pkcon install-local harbour-nami-*.rpm
```

## Building

### Architecture

- **C++ native** implementation, **CMake** build system
- **OpenCV minimal** (core, imgproc, dnn, objdetect) cross-compiled and
  bundled into the RPM
- **YuNet** face detection + **SFace** recognition, from OpenCV Zoo
- Built for `aarch64` and `armv7hl`

Packaging lives in `rpm/harbour-nami.yaml`, which is the source of truth;
`rpm/harbour-nami.spec` is regenerated from it at build time.

### CI/CD build (recommended)

Releases are cut by pushing a tag:

```bash
git tag v0.8.5 && git push origin v0.8.5
```

GitHub Actions then cross-compiles OpenCV (cached between runs), downloads the
checksum-verified ML models, builds an RPM per architecture and publishes a
release. `.github/workflows/build.yml` can also be run manually from the
Actions tab, which builds without publishing anything.

Every push to `main` additionally runs `.github/workflows/tests.yml`: QML
anti-pattern checks, JavaScript unit tests, and the Qt unit tests for the
storage and crypto layers.

### Manual build (advanced)

```bash
# 1. Download ML models
./scripts/download_models_for_build.sh

# 2. Build OpenCV minimal (inside the Sailfish SDK container)
docker run --rm \
  -v $(pwd):/home/mersdk/src:z \
  coderus/sailfishos-platform-sdk:5.0.0.43 \
  bash -c "cd /home/mersdk/src && sb2 -t SailfishOS-5.0.0.43-aarch64 bash scripts/build_opencv_minimal.sh"

# 3. Build the app
docker run --rm \
  -v $(pwd):/home/mersdk/src:z \
  coderus/sailfishos-platform-sdk:5.0.0.43 \
  bash -c "cd /home/mersdk/src && mb2 -t SailfishOS-5.0.0.43-aarch64 build"
```

### Running the checks locally

No Qt needed for the fast lane:

```bash
python3 scripts/check_qml.py   # QML anti-patterns that qmllint cannot see
node tests/js/run.js           # JavaScript unit tests
```

The Qt tests need `qtbase5-dev`, `libqt5sql5-sqlite` and `libssl-dev`:

```bash
cmake -S tests -B build-tests && cmake --build build-tests
ctest --test-dir build-tests --output-on-failure
```

## Documentation

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) - how the pieces fit together
- [docs/BUILDING.md](docs/BUILDING.md) - build details
- [docs/INSTALL.md](docs/INSTALL.md) - installation notes
- [docs/ROADMAP.md](docs/ROADMAP.md) - what is done and what is planned
- [rpm/harbour-nami.changes](rpm/harbour-nami.changes) - release notes

## License

MIT for the code (see [LICENSE](LICENSE)). The bundled ML models come from
OpenCV Zoo: YuNet under MIT, SFace under Apache-2.0.

## Contributing

Contributions are welcome. Issues and pull requests are both fine.
