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
- pytest-embedded-serial
- pytest-embedded-serial-esp
- pytest-embedded-idf
- pytest-embedded-qemu
- pytest-timeout
- pytest-cov

Each is installed at an exact version, and so is **esptool** — which this image
pins ahead of the version ESP-IDF's own constraint file names, because the harness
requires the newer line and `idf.py flash` runs whatever the environment holds.
The trade-off is written out in the Dockerfile. What a given build actually
carries is in `/opt/esp/python-packages.txt` inside the image.

## Quick Start

### Available Tags

| Tag Type | Example | Usage |
|----------|---------|-------|
| **Latest** | `latest` | Always points to newest build (floating) |
| **Version** | `idf-v<version>` | Pin to specific ESP-IDF base version (recommended for CI/CD) |
| **Commit** | `sha-<short-commit>` | Pin to exact git commit (debugging); the commit is the first 7 characters, e.g. `sha-9c281e3` |

**Several ESP-IDF versions are published at once**, each under its own
`idf-v<version>` tag; `latest` and the bare `sha-<short-commit>` follow the primary one,
chosen in [`images/versions.json`](../versions.json) — that file is also where you
can see which versions currently exist. Pin the version tag if the release matters
to you, and `idf-v<version>-sha-<short-commit>` if you need the exact build: the version
tag itself is rewritten on every rebuild.

**Tag Recommendations:**
- **Development**: Use `latest` for convenience
- **CI/CD**: Use version tags (`idf-v<version>`) for reproducibility
- **Debugging**: Use commit tags (`sha-<short-commit>`) to reproduce exact build

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
  pytest --target=esp32 --embedded-services=idf,qemu
```

### Interactive Development

```bash
docker run -it --rm \
  -v $(pwd):/workspace \
  ghcr.io/jethome-iot/jethome-dev-esp-idf:latest
```

## Supported Chips

Every ESP32 series chip the pinned ESP-IDF release supports can be built for —
run `idf.py --list-targets` inside the image for the authoritative list:

| Chip | Architecture |
|------|-------------|
| ESP32 | Xtensa |
| ESP32-S2 | Xtensa |
| ESP32-S3 | Xtensa |
| ESP32-C2 | RISC-V |
| ESP32-C3 | RISC-V |
| ESP32-C5 | RISC-V |
| ESP32-C6 | RISC-V |
| ESP32-C61 | RISC-V |
| ESP32-H2 | RISC-V |
| ESP32-P4 | RISC-V |

The table is the supported set of the **primary** ESP-IDF version. An older
version published alongside it may classify a chip differently — ESP32-C5 and
ESP32-C61 are supported in 5.5.x but preview in 5.4.x, where they need
`idf.py --preview set-target`. Preview targets are not printed by
`idf.py --list-targets`; run `idf.py --preview --list-targets` inside the image you
actually use, which is the only authoritative answer for that image.

QEMU emulation covers only part of that list — the ESP-IDF QEMU fork implements a
subset of the targets, and which ones changes as the base image is bumped. See
[QEMU for ESP32](https://docs.espressif.com/projects/esp-idf/en/stable/esp32/api-guides/tools/qemu.html)
for the current coverage.

## Usage Examples

### CI/CD Integration

Running the image as a job container replaces its entrypoint, so the ESP-IDF
environment is **not** activated automatically — source `export.sh` in each step
that calls `idf.py` or `pytest`.

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
      - uses: actions/checkout@v7
        with:
          submodules: 'recursive'
      
      - name: Build firmware
        run: . $IDF_PATH/export.sh && idf.py build
      
      - name: Run tests
        run: . $IDF_PATH/export.sh && pytest --target=esp32 --embedded-services=idf,qemu
      
      - name: Upload firmware
        uses: actions/upload-artifact@v7
        with:
          name: firmware
          path: build/*.bin
```

**GitLab CI:**

```yaml
build:
  image: ghcr.io/jethome-iot/jethome-dev-esp-idf:latest
  
  before_script:
    - . $IDF_PATH/export.sh
  
  script:
    - idf.py build
    - pytest --target=esp32 --embedded-services=idf,qemu
  
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

The image inherits these variables from the ESP-IDF base image:

```bash
IDF_PATH=/opt/esp/idf              # ESP-IDF installation path
IDF_TOOLS_PATH=/opt/esp            # ESP-IDF tools path
IDF_CCACHE_ENABLE=1                # ccache enabled by default
IDF_PYTHON_CHECK_CONSTRAINTS=no    # Skip constraint checks
```

`PATH` is not among them. The ESP-IDF tools, the QEMU binaries and the ESP-IDF
Python environment are added at container start, when the base image's entrypoint
sources `export.sh` — so they are in place for `docker run` and Docker Compose,
but not where a CI system replaces the entrypoint (see the CI/CD examples above).

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
docker build -t jethome-dev-esp-idf:local .
```

### Custom Build Arguments

```bash
docker build \
  --build-arg IDF_BASE_TAG=<version-tag> \
  -t jethome-dev-esp-idf:local .
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

- [jethome-dev-esp-matter](../esp-matter/) - ESP-Matter SDK, built `FROM` this image's `idf-v<version>` tag
- [All images in this repository](../../README.md#current-images)

