# ESP-IDF 5.4.1 Development Image

Docker image for ESP32 development with ESP-IDF 5.4.1, QEMU emulation, and comprehensive testing tools. Optimized for CI/CD pipelines and local development.

## Overview

This image provides a complete ESP-IDF development environment with additional tools for testing, code quality, and documentation. Based on the official Espressif ESP-IDF v5.4.1 image, it adds QEMU support for hardware-less testing, pytest integration, and modern development tools.

## What's Inside

**Base Environment:**
- Official `espressif/idf:v5.4.1` base image
- ESP-IDF 5.4.1 with all ESP32 toolchains
- Python 3.12.3
- Ubuntu 24.04 LTS (Noble)

**QEMU Emulation:**
- `qemu-system-xtensa` (v9.0.0) - ESP32, ESP32-S2, ESP32-S3
- `qemu-system-riscv32` (v9.0.0) - ESP32-C3, ESP32-C6
- Architecture detection (arm64/amd64)

**Testing Frameworks:**
- pytest 8.4.2
- pytest-embedded 2.2.1
- pytest-embedded-serial-esp
- pytest-embedded-idf
- pytest-embedded-qemu
- pytest-timeout
- pytest-cov
- gcovr 8.4 (code coverage)

**Code Quality Tools:**
- pylint 4.0.2
- flake8 7.3.0
- black 25.9.0

**Documentation:**
- Sphinx 8.2.3
- sphinx-rtd-theme 3.0.2

**Build Acceleration:**
- ccache (compiler cache for faster rebuilds)

**System Tools:**
- jq 1.7.1 (JSON processor)
- lcov (code coverage)
- vim, nano
- rsync
- git, curl, wget

## Quick Start

### Pull Image

```bash
docker pull ghcr.io/jethome-iot/jethome-dev-esp-idf:latest
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

### Basic ESP-IDF Commands

Inside the container (ESP-IDF environment is automatically activated):

```bash
# Create new project
idf.py create-project my_project

# Configure project
idf.py menuconfig

# Build project
idf.py build

# Clean build
idf.py fullclean

# Flash to device (requires hardware access)
idf.py flash

# Monitor serial output
idf.py monitor
```

### Testing with pytest

ESP-IDF supports pytest-embedded for automated testing:

```python
# test_example.py
import pytest

@pytest.mark.esp32
@pytest.mark.qemu
def test_app(dut):
    dut.expect('Hello world!')
```

Run tests:

```bash
# Test on QEMU
pytest --target=esp32 --embedded-services=qemu

# Test on real hardware
pytest --target=esp32 --embedded-services=esp,serial
```

### Code Coverage

Generate coverage reports:

```bash
# Build with coverage
idf.py build -DCMAKE_BUILD_TYPE=Debug

# Run tests
pytest --cov

# Generate HTML report
gcovr --html-details coverage.html
```

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

ccache is pre-configured and enabled by default. For best results when running as non-root:

**Option 1: Use Host ccache Directory (Recommended)**

```bash
# Create host ccache directory
mkdir -p ~/.cache/ccache-esp-idf

# Run with mounted ccache
docker run --rm -u $(id -u):$(id -g) \
  -v $(pwd):/workspace \
  -v ~/.cache/ccache-esp-idf:/opt/ccache \
  ghcr.io/jethome-iot/jethome-dev-esp-idf:latest \
  idf.py build

# First build: ~2-3 minutes (populates cache)
# Second build: ~30 seconds (uses cache)
```

**Option 2: Use Docker Volume (Persistent but not in host filesystem)**

```bash
# Create named volume
docker volume create esp-idf-ccache

# Run with volume
docker run --rm -u $(id -u):$(id -g) \
  -v $(pwd):/workspace \
  -v esp-idf-ccache:/opt/ccache \
  ghcr.io/jethome-iot/jethome-dev-esp-idf:latest \
  idf.py build
```

**Option 3: Temporary ccache (No persistence)**

```bash
# ccache works in /opt/ccache within container
# Cache is lost when container exits
docker run --rm -u $(id -u):$(id -g) \
  -v $(pwd):/workspace \
  ghcr.io/jethome-iot/jethome-dev-esp-idf:latest \
  idf.py build
```

**Check ccache Statistics:**

```bash
docker run --rm -u $(id -u):$(id -g) \
  -v $(pwd):/workspace \
  -v ~/.cache/ccache-esp-idf:/opt/ccache \
  ghcr.io/jethome-iot/jethome-dev-esp-idf:latest \
  ccache -s
```

### Code Quality Checks

```bash
# Python linting
pylint main/python_code.py
flake8 main/
black --check main/
```

## Environment Variables

The image inherits environment variables from the ESP-IDF base image:

```
IDF_PATH=/opt/esp/idf
IDF_TOOLS_PATH=/opt/esp
PATH includes ESP-IDF tools, QEMU binaries
```

**ccache Configuration:**
```
CCACHE_DIR=/opt/ccache
CCACHE_MAXSIZE=2G
CCACHE_COMPRESS=1
CCACHE_COMPRESSLEVEL=6
```

ESP-IDF Python environment: Automatically activated on container startup via entrypoint

QEMU binaries:
- `/opt/qemu-xtensa/bin/qemu-system-xtensa`
- `/opt/qemu-riscv32/bin/qemu-system-riscv32`

## Building the Image

### Standard Build

```bash
cd images/esp-idf
docker build -t jethome-dev-esp-idf .
```

### Custom Build Arguments

```bash
docker build \
  --build-arg ESP_IDF_VERSION=v5.4.1 \
  --build-arg QEMU_RELEASE_TAG=esp-develop-9.0.0-20240606 \
  --build-arg QEMU_VERSION=esp_develop_9.0.0_20240606 \
  -t jethome-dev-esp-idf .
```

Available build arguments:
- `ESP_IDF_VERSION` - ESP-IDF version tag (default: `v5.4.1`)
- `QEMU_RELEASE_TAG` - GitHub release tag (default: `esp-develop-9.0.0-20240606`)
- `QEMU_VERSION` - QEMU binary version string (default: `esp_develop_9.0.0_20240606`)

## Version Information

| Component | Version | Notes |
|-----------|---------|-------|
| Base Image | espressif/idf:v5.4.1 | Official Espressif image |
| ESP-IDF | 5.4.1 | Latest stable release |
| Python | 3.12.3 | Ubuntu 24.04 LTS default |
| QEMU Xtensa | 9.0.0 (esp_develop_9.0.0_20240606) | For ESP32/S2/S3 |
| QEMU RISC-V | 9.0.0 (esp_develop_9.0.0_20240606) | For ESP32-C3/C6/H2/P4 |
| pytest | 8.4.2 | Latest compatible |
| pytest-embedded | 2.2.1 | ESP-IDF integration |
| gcovr | 8.4 | Code coverage |
| Sphinx | 8.2.3 | Documentation |

## Additional Resources

- [ESP-IDF Documentation](https://docs.espressif.com/projects/esp-idf/en/stable/esp32/)
- [ESP-IDF Docker Images](https://docs.espressif.com/projects/esp-idf/en/stable/esp32/api-guides/tools/idf-docker-image.html)
- [QEMU for ESP32](https://docs.espressif.com/projects/esp-idf/en/stable/esp32/api-guides/tools/qemu.html)
- [pytest-embedded](https://docs.espressif.com/projects/pytest-embedded/en/latest/)
- [ESP32 QEMU Releases](https://github.com/espressif/qemu/releases)

## License

MIT License - see [LICENSE](../../LICENSE) file.

## Related Images

- [jethome-dev-platformio](../platformio/) - PlatformIO with ESP32 support

