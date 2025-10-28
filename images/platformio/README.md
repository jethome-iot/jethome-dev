# PlatformIO Development Image

Docker image for embedded systems development with PlatformIO, optimized for CI/CD pipelines and local builds.

## Overview

This image provides a ready-to-use PlatformIO environment with ESP32 platform support and native testing capabilities. Toolchains download automatically on first build, keeping the image size minimal while providing full functionality.

## What's Inside

**Base Environment:**
- Python 3.11 slim (Debian Bookworm)
- PlatformIO Core (latest)

**Pre-installed Platforms:**
- `espressif32@6.11.0` - ESP32 platform (all chip variants)
- `native@1.2.1` - Native platform for unit testing

**Build Tools:**
- build-essential (gcc, g++, make)
- cmake, pkg-config
- clang-format
- git, curl, wget, jq

**Python Packages:**
- protobuf - Protocol buffer support
- jinja2 - Template engine

**Testing:**
- Unity 2.6.0 - Globally installed test framework

## Quick Start

### Pull Image

```bash
docker pull ghcr.io/jethome-iot/jethome-dev-platformio:latest
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

The ESP32 platform supports all Espressif chip variants:

| Chip | Example Board | Environment Name |
|------|---------------|------------------|
| ESP32 | ESP32 DevKit | `esp32dev` |
| ESP32-S2 | ESP32-S2 Saola | `esp32-s2-saola-1` |
| ESP32-S3 | ESP32-S3 DevKitC | `esp32-s3-devkitc-1` |
| ESP32-C3 | ESP32-C3 DevKitM | `esp32-c3-devkitm-1` |
| ESP32-C6 | ESP32-C6 DevKitC | `esp32-c6-devkitc-1` |

**Note:** ESP-IDF toolchains for specific chips download automatically on first build.

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

# Run with specific user permissions
docker run --rm \
  -u $(id -u):$(id -g) \
  -v $(pwd):/workspace \
  ghcr.io/jethome-iot/jethome-dev-platformio:latest \
  pio run
```

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
docker build -t jethome-dev-platformio .
```

### Custom Build Arguments

```bash
docker build \
  --build-arg PIO_VERSION=6.1.18 \
  --build-arg ESP32_PLATFORM_VERSION=6.11.0 \
  --build-arg NATIVE_PLATFORM_VERSION=1.2.1 \
  --build-arg UNITY_VERSION=2.6.0 \
  -t jethome-dev-platformio .
```

Available build arguments:
- `PIO_VERSION` - PlatformIO Core version (default: 6.1.18)
- `ESP32_PLATFORM_VERSION` - Espressif32 platform version (default: 6.11.0)
- `NATIVE_PLATFORM_VERSION` - Native platform version (default: 1.2.1)
- `UNITY_VERSION` - Unity test framework version (default: 2.6.0)
- `PIO_ENVS` - Environments for pre-build (currently disabled)

### Multi-Platform Support

This image is built for both **linux/amd64** and **linux/arm64** architectures. Docker automatically pulls the correct image for your platform.

## Version Information

| Component | Version | Notes |
|-----------|---------|-------|
| Base Image | Python 3.11 slim | Debian Bookworm |
| PlatformIO Core | 6.1.18 | Latest stable release |
| ESP32 Platform | 6.11.0 | Version 6.12.0 has compatibility issues |
| Native Platform | 1.2.1 | For unit testing |
| Unity Framework | 2.6.0 | Globally installed |

## License

MIT License - see [LICENSE](../../LICENSE) file.

## Related

- [PlatformIO Documentation](https://docs.platformio.org/)
- [ESP-IDF Documentation](https://docs.espressif.com/projects/esp-idf/)
- [Unity Testing Framework](https://github.com/ThrowTheSwitch/Unity)
