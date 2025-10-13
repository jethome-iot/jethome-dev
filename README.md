# JetHome Development Environment

Reusable GitHub Actions for embedded development with PlatformIO.

## Quick Start

Add to your workflow:

```yaml
- uses: jethome-iot/jethome-dev/.github/actions/setup-platformio@v1
- run: pio run
```

## Available Actions

### setup-platformio

Install and cache PlatformIO Core with support for ESP-IDF framework on ESP32 microcontrollers.

**Features:**
- ⚡ Fast installation with intelligent caching
- 📌 Optional version pinning for reproducible builds  
- 🔧 Python 3.12 by default (configurable)
- 💾 Automatic caching of pip and PlatformIO packages
- 🌍 Cross-platform support (Linux, macOS, Windows)

**Basic Usage:**

```yaml
steps:
  - uses: actions/checkout@v4
  - uses: jethome-iot/jethome-dev/.github/actions/setup-platformio@v1
  - run: pio run
```

**With Options:**

```yaml
- uses: jethome-iot/jethome-dev/.github/actions/setup-platformio@v1
  with:
    version: '6.1.11'     # Pin PlatformIO version
    python-version: '3.11' # Use specific Python version
```

See [full documentation](.github/actions/setup-platformio/README.md) for more examples.

## Why Use These Actions?

- **Faster CI/CD** - Intelligent caching reduces build time by 50-80%
- **Consistent Builds** - Pin versions for reproducible builds
- **Simple Integration** - One line to add PlatformIO to any workflow
- **Cost Effective** - Reduce GitHub Actions minutes with caching
- **No Docker Overhead** - Direct installation is faster than container pulls

## Example Workflows

### Build ESP32 Project

```yaml
name: Build ESP32 Firmware
on: [push]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: jethome-iot/jethome-dev/.github/actions/setup-platformio@v1
      - run: pio run -e esp32
```

### Matrix Build for Multiple Boards

```yaml
name: Multi-Board Build
on: [push]

jobs:
  build:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        board: [esp32, esp32s2, esp32s3, esp32c3, esp32c6]
    steps:
      - uses: actions/checkout@v4
      - uses: jethome-iot/jethome-dev/.github/actions/setup-platformio@v1
      - run: pio run -e ${{ matrix.board }}
```

### Run Unit Tests

```yaml
name: Test
on: [push]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: jethome-iot/jethome-dev/.github/actions/setup-platformio@v1
      - run: pio test -e native
```

## Migration from Docker

If you're currently using Docker images for PlatformIO:

**Before (Docker):**
```yaml
- name: Build with Docker
  run: docker run --rm -v $(pwd):/workspace ghcr.io/jethome-iot/platformio:latest pio run
```

**After (Action):**
```yaml
- uses: jethome-iot/jethome-dev/.github/actions/setup-platformio@v1
- run: pio run
```

Benefits:
- ✅ Faster builds (no Docker pull/start overhead)
- ✅ Better caching (GitHub's native cache)
- ✅ Simpler workflow syntax
- ✅ Direct hardware access if needed

## Supported Platforms

The action has been tested with:
- **ESP32** - All variants (ESP32, S2, S3, C3, C6)
- **Native** - For unit testing
- **Operating Systems** - Ubuntu, macOS, Windows

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License - see [LICENSE](LICENSE) file for details.
