# JetHome Development Environment

Docker-based development environment for embedded systems, providing containerized build environments for CI/CD workflows and local development.

## Current Images

| Image | Description | Documentation |
|-------|-------------|---------------|
| [platformio](./images/platformio/) | PlatformIO with ESP32 (all variants) + ESP-IDF + Unity testing | [README](./images/platformio/README.md) |

## Quick Start

Pull the image:

```bash
docker pull ghcr.io/jethome-iot/jethome-dev-platformio:latest
```

Build your PlatformIO project:

```bash
docker run --rm -v $(pwd):/workspace \
  ghcr.io/jethome-iot/jethome-dev-platformio:latest \
  pio run
```

Interactive development:

```bash
docker run -it --rm -v $(pwd):/workspace \
  ghcr.io/jethome-iot/jethome-dev-platformio:latest
```

## What's Included

### PlatformIO Image

- **Base**: Python 3.11 slim (Debian Bookworm)
- **PlatformIO Core**: Latest version
- **Platforms**: ESP32 (6.11.0), Native (1.2.1)
- **Supported Chips**: ESP32, ESP32-S2, ESP32-S3, ESP32-C3, ESP32-C6
- **Framework**: ESP-IDF (toolchains download on first build)
- **Testing**: Unity 2.6.0 (globally installed)
- **Tools**: git, cmake, clang-format, curl, wget, jq
- **Python**: protobuf, jinja2

## Building Locally

```bash
cd images/platformio
docker build -t jethome-dev-platformio .
```

## Project Structure

```
jethome-dev/
├── images/
│   └── platformio/          # PlatformIO development image
│       ├── Dockerfile       # Image definition
│       ├── README.md        # Detailed documentation
│       └── pio_project/     # Reference configuration
├── LICENSE
└── README.md
```

## Registry

Images are published to:
- **GHCR**: `ghcr.io/jethome-iot/jethome-dev-platformio`

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
