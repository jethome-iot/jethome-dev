# ESP-Matter v1.4.2 Development Image

Docker image for ESP32 Matter device development with ESP-Matter SDK v1.4.2. Built on our ESP-IDF image, it provides a complete environment for developing Matter-compatible smart home devices.

## Overview

This image extends the `jethome-dev-esp-idf` image with Espressif's ESP-Matter SDK, enabling development of Matter protocol devices on ESP32 chips. Matter (formerly Project CHIP) is an industry-standard protocol for smart home devices, providing interoperability across platforms like Apple HomeKit, Google Home, Amazon Alexa, and others.

## What's Inside

**Base Image:**
- `jethome-dev-esp-idf:idf-v5.4.1` - Inherits all ESP-IDF tools
  - ESP-IDF 5.4.1 with all ESP32 toolchains
  - QEMU emulation (Xtensa and RISC-V)
  - pytest, pytest-embedded, testing tools
  - Python 3.12.3, Ubuntu 24.04 LTS
  - Build tools: ccache, jq, vim, nano, rsync

**ESP-Matter SDK:**
- ESP-Matter v1.4.2
- ConnectedHomeIP SDK (Matter reference implementation)
- Matter device libraries and clusters
- Example applications (light, switch, bridge, etc.)

**Matter Prerequisites:**
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

### Pull Image

```bash
docker pull ghcr.io/jethome-iot/jethome-dev-esp-matter:latest
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

### Creating a New Matter Device

```bash
# Start interactive session
docker run -it --rm -v $(pwd):/workspace \
  ghcr.io/jethome-iot/jethome-dev-esp-matter:latest

# Inside container (environment already active)
# Copy example as starting point
cp -r $ESP_MATTER_PATH/examples/light my_matter_device
cd my_matter_device

# Configure for your chip
idf.py set-target esp32c6

# Customize and build
idf.py menuconfig
idf.py build
```

### Using Matter Examples

ESP-Matter includes several ready-to-use examples:

```bash
# List available examples
ls $ESP_MATTER_PATH/examples/

# Common examples:
# - light              - Dimmable/color temperature light
# - light_switch       - On/off light switch
# - bridge             - Bridge for non-Matter devices
# - temperature_sensor - Temperature sensor
# - door_lock          - Smart lock
# - fan                - Smart fan
# - thermostat         - Temperature controller
```

### Building with Custom Data Model

```bash
# Your custom Matter device
docker run --rm -v $(pwd):/workspace \
  ghcr.io/jethome-iot/jethome-dev-esp-matter:latest \
  sh -c 'idf.py set-target esp32c6 && idf.py build'
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
CCACHE_DIR=/opt/ccache
CCACHE_MAXSIZE=2G
PATH includes ESP-IDF tools, QEMU binaries, Matter tools
```

**Automatic Environment Activation:**

The image uses a custom entrypoint (`/opt/esp-matter/entrypoint.sh`) that automatically sources both ESP-IDF and ESP-Matter environments when the container starts. This means:
- No need to run `source $IDF_PATH/export.sh`
- No need to run `source $ESP_MATTER_PATH/export.sh`
- All tools (`idf.py`, Matter CLI, etc.) are immediately available
- Works for both interactive shells and non-interactive commands

## Building the Image

### Standard Build

```bash
cd images/esp-matter
docker build -t jethome-dev-esp-matter .
```

### Custom Build Arguments

```bash
docker build \
  --build-arg ESP_IDF_VERSION=v5.4.1 \
  --build-arg ESP_MATTER_VERSION=v1.4.2 \
  -t jethome-dev-esp-matter .
```

Available build arguments:
- `ESP_IDF_VERSION` - ESP-IDF version (default: `v5.4.1`)
- `ESP_MATTER_VERSION` - ESP-Matter version tag (default: `v1.4.2`)

### Multi-Platform Support

This image is built for both **linux/amd64** and **linux/arm64** architectures. Docker automatically pulls the correct image for your platform.

## Version Information

| Component | Version | Notes |
|-----------|---------|-------|
| Base Image | jethome-dev-esp-idf:idf-v5.4.1 | Our ESP-IDF image |
| ESP-IDF | 5.4.1 | From base image |
| ESP-Matter | v1.4.2 | Matter SDK for ESP32 |
| ConnectedHomeIP | Included as submodule | Matter reference implementation |
| Python | 3.12.3 | From base image |
| Ubuntu | 24.04 LTS | From base image |
| QEMU | 9.0.0 | From base image |

## Notes

**Host Tools Not Included**: chip-tool, chip-cert, and ZAP are not included in this image to keep size minimal. For testing and commissioning, use separate controller installations or Matter-compatible platforms (Apple Home, Google Home, etc.).

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

- [jethome-dev-esp-idf](../esp-idf/) - ESP-IDF development environment (base image)
- [jethome-dev-platformio](../platformio/) - PlatformIO with ESP32 support

