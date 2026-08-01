# PlatformIO Development Image

Docker image for embedded systems development with PlatformIO, optimized for CI/CD pipelines and local builds.

## Overview

This image provides a ready-to-use PlatformIO environment with ESP32 platform support and native testing capabilities. Toolchains download automatically on first build, keeping the image size minimal while providing full functionality.

## What's Inside

**Base Environment:**
- Python slim (Debian)
- PlatformIO Core

**Pre-installed Platforms:**
- `espressif32` - ESP32 platform (all chip variants)
- `native` - Native platform for unit testing

**Build Tools:**
- build-essential (gcc, g++, make)
- cmake, pkg-config
- clang-format
- git, curl, wget, jq

**Python Packages:**
- protobuf - Protocol buffer support
- jinja2 - Template engine

**Testing:**
- Unity - Globally installed test framework

## Quick Start

### Available Tags

| Tag Type | Example | Usage |
|----------|---------|-------|
| **Latest** | `latest` | Always points to newest build (floating) |
| **Version** | `pio-v<version>` | Pin to specific PlatformIO version (recommended for CI/CD) |
| **Commit** | `sha-<commit>` | Pin to exact git commit (debugging) |
| **Platform-specific** | `pio-v<version>-linux-<arch>`, `sha-<commit>-linux-<arch>` | Single-architecture build artifacts the multi-arch tags are assembled from; not intended for direct use |

**Tag Recommendations:**
- **Development**: Use `latest` for convenience
- **CI/CD**: Use version tags (`pio-v<version>`) for reproducibility
- **Debugging**: Use commit tags (`sha-<commit>`) to reproduce exact build

### Pull Image

```bash
# Latest build
docker pull ghcr.io/jethome-iot/jethome-dev-platformio:latest

# Specific version (recommended for CI/CD)
docker pull ghcr.io/jethome-iot/jethome-dev-platformio:pio-v<version>
```

### Build Your Project

```bash
docker run --rm \
  -v $(pwd):/workspace \
  ghcr.io/jethome-iot/jethome-dev-platformio:latest \
  pio run
```

### Run Tests

```bash
docker run --rm \
  -v $(pwd):/workspace \
  ghcr.io/jethome-iot/jethome-dev-platformio:latest \
  pio test
```

### Interactive Shell

```bash
docker run -it --rm \
  -v $(pwd):/workspace \
  ghcr.io/jethome-iot/jethome-dev-platformio:latest
```

## Supported Hardware

The pinned `espressif32` platform builds for these chips. Use the board ID as the
`board` value in your `platformio.ini`; the environment name `pio run -e` takes is
whatever you write in `[env:...]`.

| Chip | Example Board | Board ID |
|------|---------------|----------|
| ESP32 | ESP32 DevKit | `esp32dev` |
| ESP32-S2 | ESP32-S2 Saola | `esp32-s2-saola-1` |
| ESP32-S3 | ESP32-S3 DevKitC | `esp32-s3-devkitc-1` |
| ESP32-C3 | ESP32-C3 DevKitM | `esp32-c3-devkitm-1` |
| ESP32-C6 | ESP32-C6 DevKitC | `esp32-c6-devkitc-1` |

**Note:** Espressif targets outside this table — ESP32-H2 and ESP32-P4 among them —
are not supported by the pinned `espressif32` version; use the ESP-IDF image for
those. ESP-IDF toolchains for the chips above download automatically on first build.

## Usage Examples

### Basic PlatformIO Commands

Inside the container:

```bash
# Check versions
pio --version
pio platform list

# Build project
pio run

# Build specific environment
pio run -e esp32

# Clean build
pio run --target clean

# Upload (requires hardware access)
pio run --target upload

# Run tests
pio test

# Run native tests only
pio test -e native
```

### CI/CD Integration

**GitHub Actions:**

```yaml
name: Build Firmware

on: [push, pull_request]

jobs:
  build:
    runs-on: ubuntu-latest
    container:
      image: ghcr.io/jethome-iot/jethome-dev-platformio:latest
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Build firmware
        run: pio run
      
      - name: Run tests
        run: pio test -e native
      
      - name: Upload artifacts
        uses: actions/upload-artifact@v4
        with:
          name: firmware
          path: .pio/build/*/firmware.bin
```

**GitLab CI:**

```yaml
build:
  image: ghcr.io/jethome-iot/jethome-dev-platformio:latest
  
  script:
    - pio run
    - pio test -e native
  
  artifacts:
    paths:
      - .pio/build/*/firmware.bin
    expire_in: 1 week
```

### Local Development

```bash
# Build and watch for changes
docker run -it --rm \
  -v $(pwd):/workspace \
  ghcr.io/jethome-iot/jethome-dev-platformio:latest \
  bash -c "while true; do pio run; sleep 5; done"
```

### Running as a non-root user

The image runs as `root` and everything under `/opt/platformio` is root-owned, so
`-u $(id -u):$(id -g)` alone fails on the first write. Redirecting
`PLATFORMIO_CORE_DIR` is not enough either: the image pins six PlatformIO
directories (see [Environment Variables](#environment-variables)), each variable
overrides only its own setting, and the rest keep pointing into `/opt/platformio`.
Redirect everything PlatformIO writes to:

```bash
docker run --rm \
  -u $(id -u):$(id -g) \
  -e PLATFORMIO_CORE_DIR=/tmp/platformio \
  -e PLATFORMIO_CACHE_DIR=/tmp/platformio/.cache \
  -e PLATFORMIO_BUILD_CACHE_DIR=/tmp/platformio/.cache/build \
  -e PLATFORMIO_PACKAGES_DIR=/tmp/platformio/packages \
  -v $(pwd):/workspace \
  ghcr.io/jethome-iot/jethome-dev-platformio:latest \
  pio run
```

Moving the package directory means toolchains and frameworks download again on the
first run — mount a volume at `/tmp/platformio` to keep them between runs. The
pre-installed platforms and the global Unity stay where the image put them and are
only read, so leave `PLATFORMIO_PLATFORMS_DIR` and `PLATFORMIO_GLOBALLIB_DIR`
alone. On Linux the `-u` flag is also what keeps build output in `/workspace`
owned by your user rather than root; Docker Desktop on macOS and Windows maps
ownership for you either way.

## Project Configuration

Example `platformio.ini` for ESP32 with ESP-IDF:

```ini
[env:esp32]
platform = espressif32
board = esp32dev
framework = espidf

[env:esp32s3]
platform = espressif32
board = esp32-s3-devkitc-1
framework = espidf

[env:native]
platform = native
test_framework = unity
```

## Environment Variables

PlatformIO directories are centralized in `/opt/platformio`:

```
PLATFORMIO_CORE_DIR=/opt/platformio
PLATFORMIO_CACHE_DIR=/opt/platformio/.cache
PLATFORMIO_PACKAGES_DIR=/opt/platformio/packages
PLATFORMIO_PLATFORMS_DIR=/opt/platformio/platforms
PLATFORMIO_GLOBALLIB_DIR=/opt/platformio/lib
PLATFORMIO_BUILD_CACHE_DIR=/opt/platformio/.cache/build
```

Your project files live in `/workspace` (mount as volume).

## Building the Image

### Standard Build

```bash
cd images/platformio
docker build -t jethome-dev-platformio:local .
```

### Custom Build Arguments

```bash
docker build \
  --build-arg PIO_VERSION=<version> \
  --build-arg ESP32_PLATFORM_VERSION=<version> \
  --build-arg NATIVE_PLATFORM_VERSION=<version> \
  --build-arg UNITY_VERSION=<version> \
  -t jethome-dev-platformio:local .
```

Available build arguments:
- `PIO_VERSION` - PlatformIO Core version (default: see Dockerfile)
- `ESP32_PLATFORM_VERSION` - Espressif32 platform version (default: see Dockerfile)
- `NATIVE_PLATFORM_VERSION` - Native platform version (default: see Dockerfile)
- `UNITY_VERSION` - Unity test framework version (default: see Dockerfile)
- `PIO_ENVS` - Environments for pre-build (currently disabled)

### Multi-Platform Support

This image is built for both **linux/amd64** and **linux/arm64** architectures. Docker automatically pulls the correct image for your platform.

## Additional Resources

- [PlatformIO Documentation](https://docs.platformio.org/)
- [ESP-IDF Documentation](https://docs.espressif.com/projects/esp-idf/)
- [Unity Testing Framework](https://github.com/ThrowTheSwitch/Unity)

## License

MIT License - see [LICENSE](../../LICENSE) file.

## Related Images

- [All images in this repository](../../README.md#current-images)
