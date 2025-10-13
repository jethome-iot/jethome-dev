# JetHome Development Environment

Development tools for embedded systems with PlatformIO - available as both GitHub Actions and Docker images.

## Quick Start

### Option 1: GitHub Action (Recommended)

Fast, cached PlatformIO installation using GitHub Actions:

```yaml
- uses: jethome-iot/jethome-dev/.github/actions/setup-platformio@v1
- run: pio run
```

### Option 2: Docker Image

Use pre-built Docker images with PlatformIO:

```bash
docker pull ghcr.io/jethome-iot/jethome-dev-platformio:latest
```

## GitHub Actions

### setup-platformio

Install and cache PlatformIO Core with support for ESP-IDF framework on ESP32 microcontrollers.

**Features:**
- ⚡ Fast installation with intelligent caching (50-80% faster than Docker)
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

## Docker Images

### jethome-dev-platformio

Pre-configured Docker image with PlatformIO and ESP32 support.

**Available Tags:**

| Tag | Description |
|-----|-------------|
| `latest`, `stable` | Latest stable release |
| `dev` | Development version |
| `YYYY.MM.DD` | Date-versioned releases |
| `monthly-YYYYMMDD` | Monthly rebuilds |

**Usage in GitHub Actions:**

```yaml
- name: Build with Docker
  run: docker run --rm -v $(pwd):/workspace ghcr.io/jethome-iot/jethome-dev-platformio:latest pio run
```

**Local Usage:**

```bash
docker run --rm -v $(pwd):/workspace ghcr.io/jethome-iot/jethome-dev-platformio:latest pio run
```

See [Docker image documentation](./images/platformio/README.md) for details.

## Example Workflows

### Using GitHub Action

```yaml
name: Build ESP32 Firmware
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

### Using Docker Image

```yaml
name: Build with Docker
on: [push]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Build firmware
        run: docker run --rm -v $(pwd):/workspace ghcr.io/jethome-iot/jethome-dev-platformio:latest pio run
```

## Comparison: Action vs Docker

| Feature | GitHub Action | Docker Image |
|---------|---------------|--------------|
| **Speed** | ✅ Faster (caching) | ⏱️ Slower (image pull) |
| **Cache** | ✅ Native GitHub cache | ❌ Limited caching |
| **Setup** | ✅ One line | ⚙️ Requires Docker |
| **Flexibility** | ✅ Configurable Python/version | ⚙️ Pre-configured |
| **Local dev** | ❌ CI/CD only | ✅ Works locally |
| **Hardware access** | ✅ Direct access | ❌ Limited in containers |

**Recommendation:** Use GitHub Action for CI/CD workflows, Docker for local development.

## Supported Platforms

Both options support:
- **ESP32** - All variants (ESP32, S2, S3, C3, C6) via ESP-IDF framework
- **Native** - For unit testing with Unity framework
- **Operating Systems** - Linux, macOS, Windows (Action only for all three)

## CI/CD

Docker images are automatically built and published to GHCR when:
- Changes are pushed to `master` branch (tagged as `latest`, `stable`, and date-versioned)
- Changes are pushed to `dev` branch (tagged as `dev`, `dev-YYYYMMDD`)
- Monthly scheduled rebuild on the 1st of each month (tagged as `monthly-YYYYMMDD`)
- Manual workflow dispatch (tagged as `manual-YYYYMMDD-HHMMSS`)

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License - see [LICENSE](LICENSE) file for details.
