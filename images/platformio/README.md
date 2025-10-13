# JetHome PlatformIO Development Image

Docker image for PlatformIO CI/CD builds with pre-installed ESP32 and native platforms.

## Features

- Python 3.11 slim base (Debian Bookworm)
- PlatformIO Core (latest)
- Supported platforms (auto-installed during build):
  - ESP32 (variants: ESP32, S2, S3, C3, C6)
  - Native platform for unit testing
- Framework: ESP-IDF (pre-downloaded for all ESP32 variants)
- Unity testing framework
- Python packages: protobuf, jinja2
- Essential build tools (build-essential, pkg-config, cmake, clang-format, git, curl, wget, jq)

## Quick Start

```bash
# Pull the image
docker pull ghcr.io/jethome-iot/jethome-dev-platformio:latest

# Run interactively
docker run -it --rm \
  -v $(pwd):/workspace \
  ghcr.io/jethome-iot/jethome-dev-platformio:latest

# For CI/CD pipelines
docker run --rm \
  -v $(pwd):/workspace \
  ghcr.io/jethome-iot/jethome-dev-platformio:latest \
  pio run --environment esp32
```

## Building Projects

Inside the container:

```bash
# Create new ESP32 project
pio init --board esp32dev --framework espidf

# Build project
pio run

# Run tests
pio test --environment native

# Build for specific environment
pio run --environment esp32
```

## Available Tags

- `latest`, `stable` - Latest stable release from master branch
- `dev` - Development version from dev branch
- `dev-YYYYMMDD` - Date-stamped dev builds
- `sha-XXXXXXX` - Specific commit builds
- `monthly-YYYYMMDD` - Monthly scheduled rebuilds (1st of each month)
- `manual-YYYYMMDD-HHMMSS` - Manual workflow dispatch builds
- `YYYY.MM.DD` - Date-based version tags

All published images are signed using [Cosign](https://github.com/sigstore/cosign) for supply chain security. You can verify image signatures using:

```bash
cosign verify ghcr.io/jethome-iot/jethome-dev-platformio:latest \
  --certificate-identity-regexp=https://github.com/jethome-iot/jethome-dev \
  --certificate-oidc-issuer=https://token.actions.githubusercontent.com
```

## Environment Variables

The image sets these PlatformIO environment variables:

- `PLATFORMIO_CORE_DIR=/opt/platformio` - Core installation
- `PLATFORMIO_CACHE_DIR=/opt/platformio/.cache` - Cache directory
- `PLATFORMIO_PACKAGES_DIR=/opt/platformio/packages` - Toolchains
- `PLATFORMIO_PLATFORMS_DIR=/opt/platformio/platforms` - Platforms
- `PLATFORMIO_GLOBALLIB_DIR=/opt/platformio/lib` - Global libraries
- `PLATFORMIO_BUILD_CACHE_DIR=/opt/platformio/.cache/build` - Build cache

Project-specific directories remain in `/workspace`.

## Pre-installed Boards

ESP32 variants with ESP-IDF framework support:
- `esp32dev` - Classic ESP32 (ESP-IDF)
- `esp32-s2-saola-1` - ESP32-S2 (ESP-IDF)
- `esp32-s3-devkitc-1` - ESP32-S3 (ESP-IDF)
- `esp32-c3-devkitm-1` - ESP32-C3 (ESP-IDF)
- `esp32-c6-devkitc-1` - ESP32-C6 (ESP-IDF)

## Volumes

Mount your project directory to `/workspace`:

```bash
docker run -v /path/to/project:/workspace ...
```

## Notes

- This image is optimized for CI/CD pipelines and build automation
- USB device access and serial monitoring tools are not included
- For local development with hardware access, consider using PlatformIO IDE or CLI directly
- All toolchains and platforms are pre-downloaded using a single `pio run` command for faster builds

## Troubleshooting

### Build Failures

Ensure your `platformio.ini` is properly configured and all dependencies are specified.

### Out of Space

Clean up old Docker images:
```bash
docker system prune -a
```

### Missing Libraries

Install project-specific libraries in your `platformio.ini`:
```ini
lib_deps = 
    SomeLibrary
```