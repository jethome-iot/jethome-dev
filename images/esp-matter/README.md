# ESP-Matter Development Image

Docker image for ESP32 Matter device development with ESP-Matter SDK. Built on our ESP-IDF image, it provides a complete environment for developing Matter-compatible smart home devices.

## Overview

This image extends the `jethome-dev-esp-idf` image with Espressif's ESP-Matter SDK, enabling development of Matter protocol devices on ESP32 chips. Matter (formerly Project CHIP) is an industry-standard protocol for smart home devices, providing interoperability across platforms like Apple HomeKit, Google Home, Amazon Alexa, and others.

## What's Inside

**Base Image:**
- [`jethome-dev-esp-idf`](../esp-idf/README.md) - inherited in full: ESP-IDF with
  all ESP32 toolchains, QEMU emulation, the pytest-embedded testing stack and the
  CI utilities it adds on top of `espressif/idf`. Its README is the authoritative
  inventory; the sections below cover only what ESP-Matter adds.

**ESP-Matter SDK:**
- ESP-Matter
- ConnectedHomeIP SDK (Matter reference implementation)
- Matter device libraries and clusters
- Example applications (light, switch, bridge, etc.)

**Matter Prerequisites:**
- python3-dev
- pkg-config
- ninja-build
- libssl-dev
- libdbus-1-dev
- libglib2.0-dev
- libavahi-client-dev

**Note on Host Tools:**
Host tools (chip-tool, chip-cert, ZAP) are **NOT included** in this image to keep size minimal. For Matter commissioning and testing, use:
- Separate chip-tool installation on host
- Matter controllers (Apple Home, Google Home, etc.)
- Python controller from connectedhomeip

## Quick Start

### Available Tags

| Tag Type | Example | Usage |
|----------|---------|-------|
| **Latest** | `latest` | Always points to newest build (floating) |
| **Version** | `idf-v<idf-ver>-matter-v<matter-ver>` | Pin to specific IDF + Matter combination (recommended for CI/CD) |
| **Commit** | `sha-<commit>` | Pin to exact git commit (debugging) |
| **Platform-specific** | `idf-v<idf-ver>-matter-v<matter-ver>-linux-<arch>`, `sha-<commit>-linux-<arch>` | Single-architecture build artifacts the multi-arch tags are assembled from; not intended for direct use |

**Tag Recommendations:**
- **Development**: Use `latest` for convenience
- **CI/CD**: Use version tags (`idf-v<idf-ver>-matter-v<matter-ver>`) for reproducibility
- **Debugging**: Use commit tags (`sha-<commit>`) to reproduce exact build

**Note**: Version tags include both ESP-IDF and ESP-Matter versions for full clarity.

### Pull Image

```bash
# Latest build
docker pull ghcr.io/jethome-iot/jethome-dev-esp-matter:latest

# Specific version (recommended for CI/CD)
docker pull ghcr.io/jethome-iot/jethome-dev-esp-matter:idf-v<idf-ver>-matter-v<matter-ver>
```

### Build Matter Example

```bash
docker run --rm \
  -v $(pwd):/workspace \
  ghcr.io/jethome-iot/jethome-dev-esp-matter:latest \
  idf.py build
```

### Interactive Development

```bash
docker run -it --rm \
  -v $(pwd):/workspace \
  ghcr.io/jethome-iot/jethome-dev-esp-matter:latest
```

Inside the container, ESP-IDF and ESP-Matter environments are automatically activated:
```bash
# Use idf.py and Matter tools directly - no sourcing needed
idf.py build
```

## Supported Chips

All ESP32 series chips with Matter support:

| Chip | Architecture | Matter Support | Thread | Wi-Fi |
|------|-------------|----------------|--------|-------|
| ESP32 | Xtensa | ⚠️ Limited | ❌ No | ✅ Yes |
| ESP32-C3 | RISC-V | ✅ Full | ✅ Yes | ✅ Yes |
| ESP32-C6 | RISC-V | ✅ Full | ✅ Yes | ✅ Yes |
| ESP32-S3 | Xtensa | ✅ Full | ✅ Yes* | ✅ Yes |
| ESP32-H2 | RISC-V | ✅ Full | ✅ Yes | ❌ No |

*ESP32-S3 with external 802.15.4 radio

## Usage Examples

### Building Matter Light Example

```bash
docker run --rm -v $(pwd):/workspace \
  ghcr.io/jethome-iot/jethome-dev-esp-matter:latest \
  sh -c 'cd $ESP_MATTER_PATH/examples/light && idf.py set-target esp32c6 && idf.py build'
```

### Using Matter Examples

ESP-Matter includes several ready-to-use examples:

```bash
# List available examples - the set changes between ESP-Matter releases, so this
# is the authoritative answer for the version your image was built from
ls $ESP_MATTER_PATH/examples/
```

### Flash and Monitor (Requires Hardware Access)

```bash
# On host with USB device access
docker run --rm -it \
  --device=/dev/ttyUSB0 \
  -v $(pwd):/workspace \
  ghcr.io/jethome-iot/jethome-dev-esp-matter:latest \
  idf.py flash monitor
```

## CI/CD Integration

Running the image as a job container replaces the entrypoint described below, so
the environments are **not** activated automatically — source both `export.sh`
scripts in each step that calls `idf.py`.

### GitHub Actions

```yaml
name: Matter Device Build

on: [push, pull_request]

jobs:
  build:
    runs-on: ubuntu-latest
    container:
      image: ghcr.io/jethome-iot/jethome-dev-esp-matter:latest
    
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: 'recursive'
      
      - name: Build Matter firmware
        run: |
          . $IDF_PATH/export.sh
          . $ESP_MATTER_PATH/export.sh
          idf.py set-target esp32c6
          idf.py build
      
      - name: Upload firmware
        uses: actions/upload-artifact@v4
        with:
          name: matter-firmware
          path: |
            build/*.bin
            build/partition_table/*.bin
```

### GitLab CI

```yaml
build-matter:
  image: ghcr.io/jethome-iot/jethome-dev-esp-matter:latest
  
  before_script:
    - . $IDF_PATH/export.sh
    - . $ESP_MATTER_PATH/export.sh
  
  script:
    - idf.py set-target esp32c6
    - idf.py build
  
  artifacts:
    paths:
      - build/*.bin
      - build/partition_table/*.bin
    expire_in: 1 week
```

### Docker Compose for Local Development

```yaml
version: '3.8'

services:
  esp-matter:
    image: ghcr.io/jethome-iot/jethome-dev-esp-matter:latest
    volumes:
      - .:/workspace
    working_dir: /workspace
    command: idf.py build
```

## Environment Variables

The image sets the following Matter-specific variables:

```bash
ESP_MATTER_PATH=/opt/esp-matter
```

**Inherited from ESP-IDF base image:**
```bash
IDF_PATH=/opt/esp/idf
IDF_TOOLS_PATH=/opt/esp
IDF_CCACHE_ENABLE=1                # ccache enabled by default
IDF_PYTHON_CHECK_CONSTRAINTS=no    # Skip constraint checks
```

`PATH` is not one of them: the ESP-IDF and ESP-Matter tools are added at container
start by the entrypoint described below.

**Automatic Environment Activation:**

The image uses a custom entrypoint (`/opt/esp/esp_matter_entrypoint.sh`, built from `entrypoint.sh` in this directory) that automatically sources both ESP-IDF and ESP-Matter environments when the container starts. This means:
- No need to run `source $IDF_PATH/export.sh`
- No need to run `source $ESP_MATTER_PATH/export.sh`
- All tools (`idf.py`, Matter CLI, etc.) are immediately available
- Works for both interactive shells and non-interactive commands

This holds for `docker run` and Docker Compose. It does **not** hold where a CI
system runs the image as a job container (GitHub Actions `container:`, GitLab
`image:`): those replace the entrypoint, so you must source both `export.sh`
scripts yourself — see the CI/CD examples above.

## Building the Image

### Standard Build

```bash
cd images/esp-matter
docker build -t jethome-dev-esp-matter:local .
```

### Custom Build Arguments

```bash
docker build \
  --build-arg BASE_IMAGE_TAG=idf-v<version> \
  --build-arg ESP_MATTER_VERSION=v<version> \
  -t jethome-dev-esp-matter:local .
```

Available build arguments:
- `BASE_IMAGE_TAG` - ESP-IDF base image tag (default: see Dockerfile)
- `ESP_MATTER_VERSION` - ESP-Matter version tag (default: see Dockerfile)

### Multi-Platform Support

This image is built for both **linux/amd64** and **linux/arm64** architectures. Docker automatically pulls the correct image for your platform.

## Additional Resources

- [ESP-Matter Documentation](https://docs.espressif.com/projects/esp-matter/en/latest/)
- [Matter Specification](https://csa-iot.org/developer-resource/specifications-download-request/)
- [ESP-Matter GitHub](https://github.com/espressif/esp-matter)
- [ConnectedHomeIP GitHub](https://github.com/project-chip/connectedhomeip)
- [Matter Device Types](https://github.com/project-chip/connectedhomeip/tree/master/src/app/clusters)
- [ESP-IDF Documentation](https://docs.espressif.com/projects/esp-idf/en/stable/esp32/)

## License

MIT License - see [LICENSE](../../LICENSE) file.

## Related Images

- [jethome-dev-esp-idf](../esp-idf/) - base image; this image is built `FROM` its `idf-v<version>` tag
- [All images in this repository](../../README.md#current-images)

