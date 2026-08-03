# JetHome Development Environment

Docker-based development environment for embedded systems, providing containerized build environments for CI/CD workflows and local development.

[![ESP-IDF Docker Image](https://github.com/jethome-iot/jethome-dev/actions/workflows/esp-idf.yml/badge.svg?branch=master)](https://github.com/jethome-iot/jethome-dev/actions/workflows/esp-idf.yml)
[![PlatformIO Docker Image](https://github.com/jethome-iot/jethome-dev/actions/workflows/platformio.yml/badge.svg?branch=master)](https://github.com/jethome-iot/jethome-dev/actions/workflows/platformio.yml)

## Current Images

| Image | Description | Documentation |
|-------|-------------|---------------|
| [esp-idf](./images/esp-idf/) | ESP-IDF for every ESP32 chip, plus pytest and QEMU emulation for some of them | [README](./images/esp-idf/README.md) |
| [esp-matter](./images/esp-matter/) | ESP-Matter SDK for Matter protocol development on ESP32 | [README](./images/esp-matter/README.md) |
| [platformio](./images/platformio/) | PlatformIO with ESP32 platform support + ESP-IDF + Unity testing | [README](./images/platformio/README.md) |

## Quick Start

Every image sets `/workspace` as its working directory and `/bin/bash` as its
default command — mount your project there and pass `-it` for an interactive
shell:

```bash
# Pull an image - <image> is its directory name, see the table above
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

**Lint Before Pushing:**

```bash
./scripts/lint.sh
```

Also worth running before a version bump:

```bash
./scripts/check-versions.sh
```

CI runs it first thing and fails the whole workflow if it does not pass. It checks
`images/versions.json` against the Dockerfiles — the versions CI passes as build
arguments must match the `ARG` defaults a local build uses, exactly one variant per
image may be `primary` (the one that gets `latest`), and an image built on another
must name a base tag that base actually publishes.

Runs the same checks as the `🧹 Lint` workflow: actionlint over the workflow files
and shellcheck over the tracked `*.sh` files are gates, hadolint over the
Dockerfiles is advisory. Both run as containers, so the Docker daemon has to be
up. The workflow itself is triggered by changes to workflows, shell scripts and
Dockerfiles.

`🔎 Runner Smoke Test` is a separate workflow: it runs a one-minute job on every
runner pool listed in `.github/actionlint.yaml` and reports architecture, vCPU,
RAM and free disk. Run it after a pool is added, renamed, or granted access to
this repository — a `runs-on` naming a pool it cannot reach does not fail, it
queues for 24 hours.

Two ways to start it: from the Actions tab (`workflow_dispatch`), or by pushing a
branch named `runner-probe/<anything>`. The second exists because
`workflow_dispatch` is only offered for workflows already on the default branch,
which would leave a change to the probe itself untestable until after it merged.
It never runs on a pull request.

**Test Workflows on GitHub Actions:**

```bash
# Workflows run on pushes and pull requests to dev or master, but only when the
# change touches that workflow's paths:
#   esp-idf.yml     -> .github/workflows/esp-idf.yml, images/esp-idf/**, images/esp-matter/**
#   platformio.yml  -> .github/workflows/platformio.yml, images/platformio/**
# Both workflows also support workflow_dispatch (Actions tab), which ignores the
# path filters. Images are pushed to GHCR from master only.
#
# In a fork nothing runs at all: the build jobs require the jethome-iot owner,
# and the runner pools they target are not reachable from a fork - a job asking
# for one would queue for 24 hours rather than fail. Build in a fork with
# ./scripts/build.sh instead. An image built FROM another image of this repo
# (today esp-matter) is also skipped on dev and on pull requests: it chains off
# the base image's manifest job, which runs on master only - see the note below.
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
`./scripts/build.sh` — it builds the same context, but as a plain `docker build`
for your host architecture only and with the Dockerfile's own `ARG` defaults
instead of the versions CI passes in, so a green local build is not a green CI
run.

**Note:** an image built `FROM` another image of this repo is not build-validated on
`dev`. Its build job needs the base image's manifest job, which runs only for
`jethome-iot` on `master` — that job publishes the multi-arch tag the derived
Dockerfile pulls. Today that is ESP-Matter: `esp-matter-build` needs
`esp-idf-manifest`, so both ESP-Matter jobs are skipped on `dev`, on pull requests,
on `workflow_dispatch` outside `master`, and in forks entirely. Every other image
builds from its own context and is validated on `dev`.

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
│   ├── actionlint.yaml      # Larger-runner pools, read by the linter and the probe
│   └── workflows/           # GitHub Actions workflows
│       ├── esp-idf.yml      # ESP-IDF and ESP-Matter image workflows
│       ├── platformio.yml   # PlatformIO image workflow
│       ├── lint.yml         # actionlint + shellcheck (gates), hadolint (advisory)
│       └── runner-smoke.yml # Reports what each runner pool actually is
├── images/
│   ├── versions.json        # Single source of truth for the versions CI builds
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
│       └── pio_project/     # Stub project for the disabled pre-build step
├── scripts/
│   ├── build.sh             # Local image build helper
│   ├── lint.sh              # Runs the same linters as CI, locally
│   ├── versions-matrix.sh   # Turns versions.json into the CI matrices
│   └── check-versions.sh    # Enforces versions.json against the Dockerfiles
├── CLAUDE.md                # Repository conventions, loaded by Claude Code
├── LICENSE
└── README.md
```

Each image directory is self-contained: the workflows build it with
`context: images/<name>`, so a Dockerfile can only `COPY` files from inside its own
directory.

## Registry

Every image is published to GitHub Container Registry (GHCR) as its own package,
named after its directory under `images/`:
`ghcr.io/jethome-iot/jethome-dev-<image>`.

See the image's own README, linked in [Current Images](#current-images), for its
available tags and usage examples.

## Use Cases

- **CI/CD**: Automated firmware builds in GitHub Actions, GitLab CI
- **Team Development**: Consistent build environment across team
- **Multi-platform**: Build for multiple ESP32 variants from a single container
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
