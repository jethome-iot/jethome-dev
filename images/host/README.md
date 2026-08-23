# Host Development Image

Docker image for building, testing and QA-checking C++ projects **on the machine
that runs them** — no cross-compiler, no target hardware. Ubuntu with GCC, CMake,
Ninja, GTest/GMock and a from-source [Eclipse Paho MQTT C](https://github.com/eclipse-paho/paho.mqtt.c)
client, plus the linters and analyzers a CI pipeline runs beside a build.

## Overview

A static analyzer reads the *host's* standard library, not the project's, so
`clang-tidy` means one thing under libc++ (macOS) and another under libstdc++
(Linux, and every CI runner): the same pinned analyzer reports findings on one and
stays silent on the other. This image is the Linux answer, reproducible on any
machine — a developer gets the CI verdict locally, on their own architecture,
without waiting for a pull-request run to tell them.

Everything it installs by name is pinned: the Python tools with `==`, the Paho
client to a commit rather than a tag, and the `lychee` and `docker` binaries to a
per-architecture SHA-256. The versions are recorded as image labels, so a
consumer can assert the image agrees with its own pins instead of assuming it
(see
[Verifying the pins](#verifying-the-pins)).

## What's Inside

**Base Environment:**
- Ubuntu (the release the tag names), matching the CI runner image
- Python 3 from the distribution, with the QA tools in a virtualenv at
  `/opt/qa-venv` that is first on `PATH`

**Build Tools:**
- build-essential (gcc, g++, make) — the sanitizer runtimes (`libasan`,
  `libubsan`, `libtsan`) come with it, so `-fsanitize=…` builds need nothing extra
- cmake, ninja-build, pkg-config
- ccache, wired into CMake builds through `CMAKE_{C,CXX}_COMPILER_LAUNCHER`, with
  its cache at `/opt/ccache`

**Libraries:**
- GTest and GMock as headers plus static archives and a CMake package config, so
  `find_package(GTest REQUIRED)` resolves
- paho.mqtt.c, built from a pinned commit and installed into `/usr/local`
  (`-DPAHO_WITH_SSL=FALSE -DPAHO_HIGH_PERFORMANCE=TRUE`, shared library)

**QA Tools:**
- clang-format, clang-tidy — same LLVM line, both pinned
- ruff, mypy, pytest, jsonschema
- lychee — offline markdown link checker
- the Docker **client** — for starting sibling containers through a mounted
  daemon socket; there is no daemon in this image (see
  [Starting sibling containers](#starting-sibling-containers))
- git, curl, jq

## Quick Start

### Available Tags

| Tag Type | Example | Usage |
|----------|---------|-------|
| **Latest** | `latest` | Always points to newest build (floating) |
| **Version** | `ubuntu-<version>` | Pin to a specific Ubuntu base (recommended for CI/CD) |
| **Commit** | `sha-<short-commit>` | Pin to exact git commit (debugging); the commit is the first 7 characters, e.g. `sha-9c281e3` |
| **Version + commit** | `ubuntu-<version>-sha-<short-commit>` | Immutable: the only tag that never moves |

**Tag Recommendations:**
- **Development**: `latest` for convenience
- **CI/CD**: the version tag for reproducibility
- **Rolling back**: `ubuntu-<version>-sha-<short-commit>` — the version tag itself is
  rewritten on every rebuild

### Pull Image

```bash
# Latest build
docker pull ghcr.io/jethome-iot/jethome-dev-host:latest

# Specific Ubuntu base (recommended for CI/CD)
docker pull ghcr.io/jethome-iot/jethome-dev-host:ubuntu-<version>
```

### Build a Project

```bash
docker run --rm \
  -u $(id -u):$(id -g) \
  -v $(pwd):/workspace \
  ghcr.io/jethome-iot/jethome-dev-host:latest \
  bash -c 'cmake -S . -B build -G Ninja && cmake --build build'
```

### Run Tests

```bash
docker run --rm \
  -u $(id -u):$(id -g) \
  -v $(pwd):/workspace \
  ghcr.io/jethome-iot/jethome-dev-host:latest \
  ctest --test-dir build --output-on-failure
```

### Run the Analyzers

```bash
# Formatting, over the files git knows about
docker run --rm -u $(id -u):$(id -g) -v $(pwd):/workspace \
  ghcr.io/jethome-iot/jethome-dev-host:latest \
  bash -c 'git ls-files "*.cpp" "*.h" | xargs clang-format --dry-run --Werror'

# Static analysis, against the compile database the build above produced. The
# image sets CMAKE_EXPORT_COMPILE_COMMANDS=ON, so an ordinary `cmake -S . -B build`
# writes build/compile_commands.json and `-p build` resolves without a second flag.
# The check set comes from the project's own .clang-tidy; with no such file
# clang-tidy has nothing enabled and exits non-zero, so name the checks instead
docker run --rm -u $(id -u):$(id -g) -v $(pwd):/workspace \
  ghcr.io/jethome-iot/jethome-dev-host:latest \
  clang-tidy -p build src/main.cpp                      # project with .clang-tidy

docker run --rm -u $(id -u):$(id -g) -v $(pwd):/workspace \
  ghcr.io/jethome-iot/jethome-dev-host:latest \
  clang-tidy '--checks=-*,bugprone-*' -p build src/main.cpp   # project without one

# Markdown links. `--offline` skips the network and checks that relative links
# resolve to files on disk; `--include-fragments` adds the #anchor check, which is
# off by default. A project with a lychee.toml of its own needs neither flag
docker run --rm -u $(id -u):$(id -g) -v $(pwd):/workspace \
  ghcr.io/jethome-iot/jethome-dev-host:latest \
  lychee --offline --include-fragments '**/*.md'
```

### Interactive Shell

```bash
docker run -it --rm \
  -v $(pwd):/workspace \
  ghcr.io/jethome-iot/jethome-dev-host:latest
```

## Running as the Invoking User

Pass `-u $(id -u):$(id -g)` and build output in `/workspace` belongs to you rather
than to root. The image is set up for it:

- `git config --system --add safe.directory '*'` — a mounted checkout is owned by
  a uid the image has no passwd entry for, and without this git refuses it as
  *dubious ownership*, taking `git ls-files` and `git describe` with it.
- `HOME=/home/build` — that uid has no home directory, and tools that write one
  would otherwise try `/`. It is a directory of the image's own rather than `/tmp`,
  which a caller is free to replace (`--tmpfs /tmp`, a volume over it, a cleanup
  step) and would take `HOME` with it mid-run.
- `CCACHE_DIR=/opt/ccache`, mode `1777` — mount a volume there to keep the cache
  between runs. Two things to know before sharing one:
  - **One uid per cache.** ccache creates its subdirectories with the creating
    user's ownership and umask, so a cache first written by one uid and then used
    by another fails with *failed to create temporary file … Permission denied*.
    Same uid, or `-e CCACHE_UMASK=000` from the start.
  - **One trust level per cache.** On a hit ccache returns the stored object file
    without re-deriving it, so a cache shared between untrusted (pull-request) and
    trusted (release) builds lets the first decide what the second links.

On Docker Desktop (macOS, Windows) ownership is mapped for you, so the flag
changes nothing; on Linux it is what keeps `build/` writable afterwards.

## Starting Sibling Containers

The image carries the Docker **client** and no daemon, so a test suite that stands
its own services up — a broker, a database — talks to the daemon of whoever runs
the image. The containers it starts are siblings of this one: they are the host's,
they do not stop when this container does, and a port they publish on `127.0.0.1`
is the *host's* loopback, not this container's.

Mount the socket:

```bash
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v $(pwd):/workspace \
  ghcr.io/jethome-iot/jethome-dev-host:latest \
  docker ps
```

**Mounting that socket is granting root on the host.** Anything that can talk to
the daemon can start a container with `--privileged` and the host's `/` mounted,
which is a complete takeover of the machine running the daemon — the container
boundary buys nothing here. Two consequences worth stating plainly:

- **Never mount it in a job that runs untrusted code.** A workflow triggered by
  `pull_request` from a fork runs the fork's code; a socket in that job hands the
  fork the runner. Keep it to jobs whose code is already trusted.
- **`--group-add` below is not a downgrade.** It restores exactly the access root
  had; the unprivileged uid is about file ownership in `/workspace`, not about the
  daemon.

**Permissions on that socket are yours to arrange, not the image's.** Running as
root — which is what a CI job `container:` does — the mounted socket just works.
Running as yourself it does not: the socket is `srw-rw----`, so an unprivileged
uid needs the group that owns it.

Take that gid from *inside* a container, not from the host. On Linux the two
agree (the host's `docker` group); on Docker Desktop they do not — the socket is
proxied into the VM and arrives owned by `0:0`, so a gid read on the Mac would be
the wrong number:

```bash
IMAGE=ghcr.io/jethome-iot/jethome-dev-host:latest
SOCK_GID=$(docker run --rm -v /var/run/docker.sock:/var/run/docker.sock "$IMAGE" \
             stat -c '%g' /var/run/docker.sock)

docker run --rm \
  -u $(id -u):$(id -g) \
  --group-add "$SOCK_GID" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v $(pwd):/workspace \
  "$IMAGE" \
  docker ps
```

**Paths in a sibling's `-v` are resolved by the daemon, on the host.** They are
not paths in this container. `docker run -v /workspace/fixtures:/etc/mosquitto`
from in here asks the *host* for `/workspace/fixtures`, which usually does not
exist — and the daemon then creates it empty rather than failing, so the service
starts with defaults and the test fails somewhere else entirely. Pass the host
path (the one you mounted at `/workspace`), or hand the sibling its data another
way.

**Reaching a service the sibling publishes.** From inside this container,
`127.0.0.1` is this container — so a broker the sibling published on the *host's*
loopback is not there. `host.docker.internal` is the address that reaches it:
Docker Desktop resolves it with no extra flag, and on Linux it takes
`--add-host=host.docker.internal:host-gateway` on this container plus a service
published on `0.0.0.0` rather than on loopback. Whichever the consuming project
picks, the address it hands its tests has to resolve *in here*.

## Verifying the Pins

The image records what it was built with as OCI labels, so a project that pins the
same tools can assert the two agree rather than trusting the tag:

```bash
docker inspect --format '{{json .Config.Labels}}' \
  ghcr.io/jethome-iot/jethome-dev-host:latest | jq .
```

```text
dev.jethome.paho.version, dev.jethome.paho.ref        # tag and the exact commit
dev.jethome.clang-tidy.version, …clang-format.version
dev.jethome.ruff.version, …mypy.version, …pytest.version, …jsonschema.version
dev.jethome.lychee.version, …docker-cli.version
```

The Python environment carries its own snapshot at `/opt/qa-packages.txt`
(`pip freeze` as of the build), which includes the transitive dependencies the
labels do not name.

## What It Does Not Carry

- **No Docker daemon.** The client is present, but it needs a daemon to talk to:
  mount the host's socket and the containers it starts are siblings of this one,
  never children of it ([Starting sibling containers](#starting-sibling-containers)).
- **No CLI plugins at all** — no `compose`, and no `buildx` either: the client is
  extracted from Docker's static release, which ships none. A service record
  spelled as `docker run` needs nothing else; one spelled as a compose file does.
  `docker build` still works, because the daemon builds — it falls back to the
  classic builder, so BuildKit-only Dockerfile features are out.
- **No cross-compilers and no target SDKs.** Firmware targets are the job of the
  other images in [the repository index](../../README.md#current-images).
- **No TLS in the MQTT client.** Paho is built with `PAHO_WITH_SSL=FALSE`, so
  `paho-mqtt3a` and `paho-mqtt3c` are present and `paho-mqtt3as`/`paho-mqtt3cs`
  are not.
- **The distribution's Python**, not a specific minor. If a project's own CI pins
  an interpreter version, its `pytest` legs run here on a different one; linters
  are unaffected where the target version is set in configuration
  (`python_version` for mypy, `target-version` for ruff) rather than taken from
  the interpreter.

## Usage Examples

### CI/CD Integration

**GitHub Actions:**

```yaml
name: Build and test

on: [push, pull_request]

jobs:
  posix:
    runs-on: ubuntu-latest
    container:
      image: ghcr.io/jethome-iot/jethome-dev-host:latest

    steps:
      - uses: actions/checkout@v7

      - name: Configure and build
        run: |
          cmake -S . -B build -G Ninja
          cmake --build build

      - name: Test
        run: ctest --test-dir build --output-on-failure

      - name: Lint
        run: |
          ruff check .
          mypy
```

A job that also needs the daemon — one that stands a service up as a sibling
container — asks for the socket through `container.options`, and only on a
trigger whose code is trusted (see the warning in
[Starting sibling containers](#starting-sibling-containers)):

```yaml
    container:
      image: ghcr.io/jethome-iot/jethome-dev-host:latest
      options: --volume /var/run/docker.sock:/var/run/docker.sock
```

**GitLab CI:**

```yaml
posix:
  image: ghcr.io/jethome-iot/jethome-dev-host:latest

  script:
    - cmake -S . -B build -G Ninja
    - cmake --build build
    - ctest --test-dir build --output-on-failure
```

### Sanitizer Builds

```bash
docker run --rm -u $(id -u):$(id -g) -v $(pwd):/workspace \
  ghcr.io/jethome-iot/jethome-dev-host:latest \
  bash -c 'cmake -S . -B build-asan -G Ninja \
             -DCMAKE_BUILD_TYPE=Debug \
             -DCMAKE_CXX_FLAGS="-fsanitize=address,undefined" && \
           cmake --build build-asan'
```

## Environment Variables

```
VIRTUAL_ENV=/opt/qa-venv           # the QA virtualenv, first on PATH
HOME=/home/build                   # the invoking uid has no home directory; 1777
CCACHE_DIR=/opt/ccache             # 1777; mount a volume to persist it
CMAKE_C_COMPILER_LAUNCHER=ccache   # what actually puts ccache in the build
CMAKE_CXX_COMPILER_LAUNCHER=ccache # override with -DCMAKE_CXX_COMPILER_LAUNCHER=
CMAKE_EXPORT_COMPILE_COMMANDS=ON   # so clang-tidy -p <build-dir> just works
```

Your project files live in `/workspace` (mount as volume).

## Building the Image

### Standard Build

```bash
cd images/host
docker build -t jethome-dev-host:local .
```

Or from the repository root: `./scripts/build.sh host`.

### Custom Build Arguments

```bash
docker build \
  --build-arg UBUNTU_BASE_TAG=<tag> \
  --build-arg CLANG_TIDY_VERSION=<version> \
  --build-arg PAHO_REF=<commit> \
  -t jethome-dev-host:local .
```

Available build arguments (defaults: see the Dockerfile):
- `UBUNTU_BASE_TAG` — the Ubuntu base image tag; the only argument CI passes, and
  the one the image tag names
- `RUFF_VERSION`, `MYPY_VERSION`, `PYTEST_VERSION`, `JSONSCHEMA_VERSION` — the
  Python QA tools
- `CLANG_FORMAT_VERSION`, `CLANG_TIDY_VERSION` — the LLVM tools; the verification
  layer asserts the installed binaries report these numbers
- `PAHO_VERSION`, `PAHO_REF`, `PAHO_REPO` — the MQTT client's tag, exact commit and
  origin. `PAHO_VERSION` is what the built library is checked against, so it and
  `PAHO_REF` are bumped together
- `LYCHEE_VERSION`, `LYCHEE_SHA256_AMD64`, `LYCHEE_SHA256_ARM64` — the link
  checker's release and its per-architecture checksums; a version bump edits all
  three
- `DOCKER_VERSION`, `DOCKER_SHA256_AMD64`, `DOCKER_SHA256_ARM64` — the Docker
  client, taken from Docker's static release and verified the same way. Docker
  publishes no `.sha256` beside those tarballs, so both sums are literals here and
  a bump recomputes them

The last layer of the build is a verification step, and it asserts rather than
lists: it prints every tool's version, requires the two clang tools and the Docker
client to report the pinned numbers and `jsonschema` to appear at its pinned
version in the freeze,
then configures, builds and `ctest`s the small CMake project in
[`smoke/`](./smoke/) — proving that `find_package(GTest)` resolves, that GMock
links, that CMake took the ccache launcher, and that the Paho library loaded
reports the pinned version. It finishes by running `clang-tidy` over that
project's own source against the compile database the build wrote, so an analyzer
that answers `--version` but cannot find its resource directory fails the image
instead of the user's first run.

The sources stay in the image at `/opt/smoke-src`, so the same check runs against
a published image:

```bash
IMAGE=ghcr.io/jethome-iot/jethome-dev-host:latest
# The version to check against comes from the image's own label, so this does not
# repeat a number that lives in the Dockerfile
PAHO=$(docker inspect --format '{{index .Config.Labels "dev.jethome.paho.version"}}' "$IMAGE")

docker run --rm -e PAHO="$PAHO" "$IMAGE" bash -c '
  cmake -S /opt/smoke-src -B /tmp/smoke -G Ninja -DPAHO_EXPECTED_VERSION="$PAHO" >/dev/null &&
  cmake --build /tmp/smoke >/dev/null &&
  ctest --test-dir /tmp/smoke --output-on-failure'
```

### Multi-Platform Support

This image is built for both **linux/amd64** and **linux/arm64**, each on a runner
of its own architecture. Docker pulls the right one for your machine — an Apple
Silicon developer gets a native image rather than an emulated one.

## Additional Resources

- [GoogleTest](https://google.github.io/googletest/)
- [Eclipse Paho MQTT C](https://eclipse.dev/paho/index.php?page=clients/c/index.php)
- [clang-tidy](https://clang.llvm.org/extra/clang-tidy/)
- [lychee](https://lychee.cli.rs/)

## License

MIT License - see [LICENSE](../../LICENSE) file.

## Related Images

- [All images in this repository](../../README.md#current-images)
