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

Every image mounts your project at `/workspace` and starts an interactive shell by
default:

```bash
# Pull image (esp-idf, esp-matter or platformio)
docker pull ghcr.io/jethome-iot/jethome-dev-<image>:latest

# Interactive development
docker run -it --rm -v $(pwd):/workspace \
  ghcr.io/jethome-iot/jethome-dev-<image>:latest
```

The build command differs per image (`idf.py` for esp-idf and esp-matter, `pio`
for platformio). What each image contains, its supported chips, available tags,
build arguments and ready-to-run examples are documented in the image README
linked in the table above.

## Local Development

### Helper Script

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

**Test Workflows on GitHub Actions:**

```bash
# Workflows run on pushes and pull requests to dev or master, but only when the
# change touches that workflow's paths:
#   esp-idf.yml     -> .github/workflows/esp-idf.yml, images/esp-idf/**, images/esp-matter/**
#   platformio.yml  -> .github/workflows/platformio.yml, images/platformio/**
# Both workflows also support workflow_dispatch (Actions tab), which ignores the
# path filters. Images are pushed to GHCR from master only.
git checkout dev
git push origin dev

# Monitor workflow progress
gh run list --workflow="🐳 ESP-IDF Docker Image" --limit 5
gh run watch

# View logs
gh run view <run-id> --log
```

Requires [GitHub CLI](https://cli.github.com/) to be installed.

There is no local workflow runner: workflow changes are validated by pushing the
branch and reading the PR's checks. To iterate on a Dockerfile itself, use
`./scripts/build.sh` — it builds the same image the workflow does.

**Note:** only the ESP-IDF and PlatformIO images are build-validated on `dev`. The
ESP-Matter jobs depend on `esp-idf-manifest`, which runs only for `jethome-iot` on
`master` — ESP-Matter is built `FROM` the published multi-arch ESP-IDF tag that job
creates — so they are skipped on `dev`, on pull requests, on `workflow_dispatch`
outside `master`, and in forks entirely.

A change touching only `images/esp-matter/**` still matches the workflow's path
filter, so `esp-idf-build` runs on its unchanged context and the check reports
success: a green "🐳 ESP-IDF Docker Image" on such a PR does **not** mean the
ESP-Matter image compiles. Validate it locally with
`./scripts/build.sh esp-matter` (~50GB of disk, several hours) or on `master`.

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
│   │   ├── entrypoint.sh    # Activates ESP-IDF + ESP-Matter env on start
│   │   └── README.md        # Detailed documentation
│   └── platformio/          # PlatformIO development image
│       ├── Dockerfile       # Image definition
│       ├── README.md        # Detailed documentation
│       └── pio_project/     # Reference configuration
├── scripts/
│   └── build.sh             # Local image build helper
├── CLAUDE.md                # Repository conventions, loaded by Claude Code
├── LICENSE
└── README.md
```

Each image directory is self-contained: the workflows build it with
`context: images/<name>`, so a Dockerfile can only `COPY` files from inside its own
directory.

## Registry

Images are published to GitHub Container Registry (GHCR):
- **ESP-IDF**: `ghcr.io/jethome-iot/jethome-dev-esp-idf`
- **ESP-Matter**: `ghcr.io/jethome-iot/jethome-dev-esp-matter`
- **PlatformIO**: `ghcr.io/jethome-iot/jethome-dev-platformio`

See individual image documentation for available tags and usage examples.

## Use Cases

- **CI/CD**: Automated firmware builds in GitHub Actions, GitLab CI
- **Team Development**: Consistent build environment across team
- **Multi-platform**: Build for all ESP32 variants from single container
- **Testing**: Native platform for unit tests with Unity framework

## Features

- ✅ Reproducible builds across all machines — images are pinned by version tags
- ✅ Multi-architecture: every image is published for `linux/amd64` and `linux/arm64`
- ✅ Multiple ESP32 chip variants supported by a single image
- ✅ Images kept minimal — toolchains that are not needed at build time download on
  first use
- ✅ CI/CD optimized (no USB/serial dependencies)

## License

MIT License - see [LICENSE](LICENSE) file for details.

---

**Note**: More development images may be added in the future.
