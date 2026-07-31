# ESP-IDF Development Image

Docker image for ESP32 development with ESP-IDF and testing tools. Optimized for CI/CD pipelines and local development.

## Overview

This image extends the official Espressif ESP-IDF image with additional tools for testing and CI/CD integration. It provides pytest frameworks for hardware-in-the-loop and QEMU-based testing, plus utilities for code coverage and build automation.

## What's Inside

**Base Environment (from espressif/idf):**
- ESP-IDF with all ESP32 toolchains
- Python
- Ubuntu LTS
- QEMU emulation (qemu-system-xtensa, qemu-system-riscv32)
- ccache (compiler cache)
- Standard build tools (git, curl, wget, cmake, ninja)

**Additional Tools (added by this image):**
- **jq** - JSON processor for CI/CD scripting
- **gcovr** - Code coverage reporting

**Testing Frameworks:**
- pytest
- pytest-embedded
- pytest-embedded-serial-esp
- pytest-embedded-idf
- pytest-embedded-qemu
- pytest-timeout
- pytest-cov

## Quick Start

### Available Tags

| Tag Type | Example | Usage |
|----------|---------|-------|
| **Latest** | `latest` | Always points to newest build (floating) |
| **Version** | `idf-v<version>` | Pin to specific ESP-IDF base version (recommended for CI/CD) |
| **Commit** | `sha-<commit>` | Pin to exact git commit (debugging) |
| **Platform-specific** | `idf-v<version>-linux-<arch>`, `sha-<commit>-linux-<arch>` | Single-architecture build artifacts the multi-arch tags are assembled from; not intended for direct use |

**Tag Recommendations:**
- **Development**: Use `latest` for convenience
- **CI/CD**: Use version tags (`idf-v<version>`) for reproducibility
- **Debugging**: Use commit tags (`sha-<commit>`) to reproduce exact build

### Pull Image

```bash
# Latest build
docker pull ghcr.io/jethome-iot/jethome-dev-esp-idf:latest

# Specific version (recommended for CI/CD)
docker pull ghcr.io/jethome-iot/jethome-dev-esp-idf:idf-v<version>
```

### Build Your Project

```bash
docker run --rm \
  -v $(pwd):/workspace \
  ghcr.io/jethome-iot/jethome-dev-esp-idf:latest \
  idf.py build
```

### Run Tests with QEMU

```bash
docker run --rm \
  -v $(pwd):/workspace \
  ghcr.io/jethome-iot/jethome-dev-esp-idf:latest \
  pytest --target=esp32
```

### Interactive Development

```bash
docker run -it --rm \
  -v $(pwd):/workspace \
  ghcr.io/jethome-iot/jethome-dev-esp-idf:latest
```

## Supported Chips

All ESP32 series chips are supported:

| Chip | Architecture | QEMU Support |
|------|-------------|--------------|
| ESP32 | Xtensa | ✅ Yes |
| ESP32-S2 | Xtensa | ✅ Yes |
| ESP32-S3 | Xtensa | ✅ Yes |
| ESP32-C3 | RISC-V | ✅ Yes |
| ESP32-C6 | RISC-V | ✅ Yes |
| ESP32-H2 | RISC-V | ✅ Yes |
| ESP32-P4 | RISC-V | ✅ Yes |

## Usage Examples

### CI/CD Integration

**GitHub Actions:**

```yaml
name: ESP-IDF Build

on: [push, pull_request]

jobs:
  build:
    runs-on: ubuntu-latest
    container:
      image: ghcr.io/jethome-iot/jethome-dev-esp-idf:latest
    
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: 'recursive'
      
      - name: Build firmware
        run: idf.py build
      
      - name: Run tests
        run: pytest --target=esp32 --embedded-services=qemu
      
      - name: Upload firmware
        uses: actions/upload-artifact@v4
        with:
          name: firmware
          path: build/*.bin
```

**GitLab CI:**

```yaml
build:
  image: ghcr.io/jethome-iot/jethome-dev-esp-idf:latest
  
  script:
    - idf.py build
    - pytest --target=esp32 --embedded-services=qemu
  
  artifacts:
    paths:
      - build/*.bin
    expire_in: 1 week
```

### Local Development with Docker Compose

```yaml
version: '3.8'

services:
  esp-idf:
    image: ghcr.io/jethome-iot/jethome-dev-esp-idf:latest
    volumes:
      - .:/workspace
    working_dir: /workspace
    command: idf.py build
```

### Using ccache for Faster Builds

ccache is included in the base image and enabled by default (`IDF_CCACHE_ENABLE=1`). To persist the cache between container runs, mount a host directory or Docker volume:

**Option 1: Use Host ccache Directory (Recommended)**

```bash
# Create host ccache directory
mkdir -p ~/.cache/ccache-esp-idf

# Run with mounted ccache and custom configuration
docker run --rm \
  -v $(pwd):/workspace \
  -v ~/.cache/ccache-esp-idf:/ccache \
  -e CCACHE_DIR=/ccache \
  -e CCACHE_MAXSIZE=5G \
  ghcr.io/jethome-iot/jethome-dev-esp-idf:latest \
  idf.py build

# First build: populates cache
# Subsequent builds: significantly faster with cache
```

**Option 2: Use Docker Volume**

```bash
# Create named volume
docker volume create esp-idf-ccache

# Run with volume
docker run --rm \
  -v $(pwd):/workspace \
  -v esp-idf-ccache:/ccache \
  -e CCACHE_DIR=/ccache \
  ghcr.io/jethome-iot/jethome-dev-esp-idf:latest \
  idf.py build
```

**Option 3: Use Default Location**

```bash
# ccache uses default location (~/.ccache in container)
# Cache is lost when container exits
docker run --rm \
  -v $(pwd):/workspace \
  ghcr.io/jethome-iot/jethome-dev-esp-idf:latest \
  idf.py build
```

**Check ccache Statistics:**

```bash
docker run --rm \
  -v ~/.cache/ccache-esp-idf:/ccache \
  -e CCACHE_DIR=/ccache \
  ghcr.io/jethome-iot/jethome-dev-esp-idf:latest \
  ccache -s
```

**ccache Environment Variables:**

You can customize ccache behavior with environment variables:
- `CCACHE_DIR` - Cache directory location
- `CCACHE_MAXSIZE` - Maximum cache size (e.g., `5G`)
- `CCACHE_COMPRESS` - Enable compression (`1` or `0`)
- `CCACHE_COMPRESSLEVEL` - Compression level (`1`-`9`)

See [ccache documentation](https://ccache.dev/manual/latest.html) for all options.

## Environment Variables

The image inherits environment variables from the ESP-IDF base image:

```bash
IDF_PATH=/opt/esp/idf              # ESP-IDF installation path
IDF_TOOLS_PATH=/opt/esp            # ESP-IDF tools path
IDF_CCACHE_ENABLE=1                # ccache enabled by default
IDF_PYTHON_CHECK_CONSTRAINTS=no    # Skip constraint checks
PATH includes ESP-IDF tools and QEMU binaries
```

**ESP-IDF Python environment:** Automatically activated on container startup via entrypoint

**Configure ccache** (optional):
```bash
docker run -e CCACHE_DIR=/ccache -e CCACHE_MAXSIZE=5G ...
```

See ccache section above for detailed configuration options.

## Building the Image

### Standard Build

```bash
cd images/esp-idf
docker build -t jethome-dev-esp-idf .
```

### Custom Build Arguments

```bash
docker build \
  --build-arg IDF_BASE_TAG=<version-tag> \
  -t jethome-dev-esp-idf .
```

Available build arguments:
- `IDF_BASE_TAG` - Base image tag from espressif/idf (e.g., `v5.4.1`, `v5.3`, `latest`)

### Multi-Platform Support

This image is built for both **linux/amd64** and **linux/arm64** architectures. Docker automatically pulls the correct image for your platform.

## Additional Resources

- [ESP-IDF Documentation](https://docs.espressif.com/projects/esp-idf/en/stable/esp32/)
- [ESP-IDF Docker Images](https://docs.espressif.com/projects/esp-idf/en/stable/esp32/api-guides/tools/idf-docker-image.html)
- [QEMU for ESP32](https://docs.espressif.com/projects/esp-idf/en/stable/esp32/api-guides/tools/qemu.html)
- [pytest-embedded](https://docs.espressif.com/projects/pytest-embedded/en/latest/)

## License

MIT License - see [LICENSE](../../LICENSE) file.

## Related Images

- [jethome-dev-platformio](../platformio/) - PlatformIO with ESP32 support

