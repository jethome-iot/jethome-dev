# JetHome Development Environment

Docker-based development environment for embedded systems, providing containerized build environments for CI/CD workflows and local development.

[![ESP-IDF Docker Image](https://github.com/jethome-iot/jethome-dev/actions/workflows/esp-idf.yml/badge.svg?branch=master)](https://github.com/jethome-iot/jethome-dev/actions/workflows/esp-idf.yml)
[![PlatformIO Docker Image](https://github.com/jethome-iot/jethome-dev/actions/workflows/platformio.yml/badge.svg?branch=master)](https://github.com/jethome-iot/jethome-dev/actions/workflows/platformio.yml)

## Current Images

| Image | Description | Documentation |
|-------|-------------|---------------|
| [esp-idf](./images/esp-idf/) | ESP-IDF with QEMU, pytest, and testing tools for all ESP32 chips | [README](./images/esp-idf/README.md) |
| [esp-matter](./images/esp-matter/) | ESP-Matter SDK for Matter protocol development on ESP32 | [README](./images/esp-matter/README.md) |
| [platformio](./images/platformio/) | PlatformIO with ESP32 (all variants) + ESP-IDF + Unity testing | [README](./images/platformio/README.md) |

## Quick Start

### ESP-IDF

```bash
# Pull image
docker pull ghcr.io/jethome-iot/jethome-dev-esp-idf:latest

# Build project
docker run --rm -v $(pwd):/workspace \
  ghcr.io/jethome-iot/jethome-dev-esp-idf:latest \
  idf.py build

# Interactive development
docker run -it --rm -v $(pwd):/workspace \
  ghcr.io/jethome-iot/jethome-dev-esp-idf:latest
```

### ESP-Matter

```bash
# Pull image
docker pull ghcr.io/jethome-iot/jethome-dev-esp-matter:latest

# Build Matter project
docker run --rm -v $(pwd):/workspace \
  ghcr.io/jethome-iot/jethome-dev-esp-matter:latest \
  idf.py build

# Interactive development
docker run -it --rm -v $(pwd):/workspace \
  ghcr.io/jethome-iot/jethome-dev-esp-matter:latest
```

### PlatformIO

```bash
# Pull image
docker pull ghcr.io/jethome-iot/jethome-dev-platformio:latest

# Build project
docker run --rm -v $(pwd):/workspace \
  ghcr.io/jethome-iot/jethome-dev-platformio:latest \
  pio run

# Interactive development
docker run -it --rm -v $(pwd):/workspace \
  ghcr.io/jethome-iot/jethome-dev-platformio:latest
```

## What's Included

### ESP-IDF Image

- **Base**: Official espressif/idf (Ubuntu LTS)
- **ESP-IDF**: All ESP32 toolchains included in base image
- **QEMU**: Xtensa and RISC-V emulation support (from base image)
- **Supported Chips**: ESP32, ESP32-S2, ESP32-S3, ESP32-C3, ESP32-C6, ESP32-H2, ESP32-P4
- **Additional Tools**: jq (JSON processor), gcovr (code coverage)
- **Testing**: pytest, pytest-embedded frameworks for ESP-IDF and QEMU

### ESP-Matter Image

- **Base**: jethome-dev-esp-idf (inherits all ESP-IDF tools)
- **ESP-Matter**: ConnectedHomeIP SDK included
- **Matter Protocol**: Support for Matter 1.0 and 1.1 (partial)
- **Supported Chips**: ESP32-C3, ESP32-C6, ESP32-S3, ESP32-H2 (full Matter support)
- **Features**: Matter device clusters, commissioning, OTA updates
- **Examples**: Light, switch, bridge, temperature sensor, door lock, fan, thermostat
- **Note**: Host tools (chip-tool, chip-cert) not included for minimal image size

### PlatformIO Image

- **Base**: Python slim (Debian)
- **PlatformIO Core**: Latest version
- **Platforms**: ESP32, Native
- **Supported Chips**: ESP32, ESP32-S2, ESP32-S3, ESP32-C3, ESP32-C6
- **Framework**: ESP-IDF (toolchains download on first build)
- **Testing**: Unity (globally installed)
- **Tools**: git, cmake, clang-format, curl, wget, jq
- **Python**: protobuf, jinja2

## Local Development

### Helper Scripts

The repository includes helper scripts in the `scripts/` directory for local development:

**Build Images Locally:**

```bash
# Interactive mode - select image to build and run
./scripts/build.sh

# Build specific image (tagged as 'local')
./scripts/build.sh esp-idf
./scripts/build.sh platformio

# Build and run image interactively
./scripts/build.sh -r esp-idf
./scripts/build.sh --run platformio

# Build with custom tag
IMAGE_TAG=dev ./scripts/build.sh esp-idf

# Build all images
./scripts/build.sh all
```

The script builds images with the `local` tag by default to distinguish them from registry images. Use the `-r` or `--run` flag to automatically run the image in interactive mode after a successful build. You can customize the tag using the `IMAGE_TAG` environment variable.

**Test Workflows with act:**

```bash
# Interactive mode - select workflow to test
./scripts/test-workflow.sh

# Test specific workflow (dry-run)
./scripts/test-workflow.sh esp-idf

# Test all workflows
./scripts/test-workflow.sh all

# Actually run workflow (not dry-run)
./scripts/test-workflow.sh esp-idf --no-dryrun
```

Requires [act](https://github.com/nektos/act) to be installed.

**Test Workflows on GitHub Actions:**

```bash
# Workflows are triggered automatically by pushing to dev or master branches
# Push to dev for testing (build-only, no push to GHCR)
git checkout dev
git push origin dev

# Monitor workflow progress
gh run list --workflow="🐳 ESP-IDF Docker Image" --limit 5
gh run watch

# View logs
gh run view <run-id> --log
```

Requires [GitHub CLI](https://cli.github.com/) to be installed.

### Manual Building

```bash
cd images/platformio
docker build -t jethome-dev-platformio:local .
```

**Note:** Locally built images use the `local` tag by default to distinguish them from registry images tagged with `latest`.

## Project Structure

```
jethome-dev/
├── .github/
│   └── workflows/           # GitHub Actions workflows
│       ├── esp-idf.yml      # ESP-IDF and ESP-Matter image workflows
│       └── platformio.yml   # PlatformIO image workflow
├── images/
│   ├── esp-idf/             # ESP-IDF development image
│   │   ├── Dockerfile       # Image definition
│   │   └── README.md        # Detailed documentation
│   ├── esp-matter/          # ESP-Matter development image
│   │   ├── Dockerfile       # Image definition
│   │   └── README.md        # Detailed documentation
│   └── platformio/          # PlatformIO development image
│       ├── Dockerfile       # Image definition
│       ├── README.md        # Detailed documentation
│       └── pio_project/     # Reference configuration
├── scripts/
│   ├── build.sh             # Local image build helper
│   └── test-workflow.sh     # Workflow testing with act
├── LICENSE
└── README.md
```

## Registry

Images are published to GitHub Container Registry (GHCR):
- **ESP-IDF**: `ghcr.io/jethome-iot/jethome-dev-esp-idf`
- **ESP-Matter**: `ghcr.io/jethome-iot/jethome-dev-esp-matter`
- **PlatformIO**: `ghcr.io/jethome-iot/jethome-dev-platformio`

## Use Cases

- **CI/CD**: Automated firmware builds in GitHub Actions, GitLab CI
- **Team Development**: Consistent build environment across team
- **Multi-platform**: Build for all ESP32 variants from single container
- **Testing**: Native platform for unit tests with Unity framework

## Features

- ✅ Reproducible builds across all machines
- ✅ ESP32 and Native platforms pre-installed
- ✅ Toolchains download automatically on first build
- ✅ Minimal image size (Python slim base)
- ✅ CI/CD optimized (no USB/serial dependencies)
- ✅ Multiple ESP32 chip support in one image

## License

MIT License - see [LICENSE](LICENSE) file for details.

---

**Note**: More development images may be added in the future.
