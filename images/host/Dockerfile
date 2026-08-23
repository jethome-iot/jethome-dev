# JetHome host development image
#
# Builds and tests the POSIX target of a C++ firmware project on the machine it
# runs on, and carries the QA gates that project runs beside the build: ruff,
# mypy, pytest, clang-format, clang-tidy and lychee. It also carries the Docker
# client — no daemon — so a suite that stands its own services up can do it
# through a socket the caller mounts.
#
# Why an image rather than a list of `apt-get install` lines in a CI job: a static
# analyzer reads the *host's* standard library, not the project's. libc++ (macOS)
# inlines the `throw` inside `std::string` and `std::function`; libstdc++ (Linux,
# and every CI runner) hides them behind external `__throw_*` the analyzer cannot
# look into. Same pinned clang-tidy, different findings - so "clang-tidy is green"
# means one thing on a developer's laptop and another in CI. This image is the
# second one, reproducible on either machine.
#
# Ubuntu, and the same release the CI runners use, for exactly that reason. Built
# for linux/amd64 AND linux/arm64 - an Apple Silicon developer must not land in
# QEMU, where the analysis they are waiting on takes an order of magnitude longer.
#
# The base tag is an ARG because images/versions.json requires every value it
# passes in `args` to appear in the variant's tag - that is what binds a published
# tag to the base it advertises. The tool versions below are deliberately NOT args:
# a tool version can never appear in the tag, so the same rule would reject it.
# They live as ARG defaults here, which is the regime images/versions.json's
# _readme describes for exactly this case, and ./scripts/check-pins.sh is what
# holds them to an exact version.
ARG UBUNTU_BASE_TAG=24.04

FROM ubuntu:${UBUNTU_BASE_TAG}

# An ARG, not an ENV: this answers apt during the build and has no business
# reaching a shell the user opens later.
ARG DEBIAN_FRONTEND=noninteractive

# ── apt: the build, the host tests, and the tools the project's scripts call ──
#
# GTest and GMock arrive as libraries and headers already built (Ubuntu ships
# .a archives plus the CMake package config), so a project consuming this image
# can `find_package(GTest)` and link - the verification layer at the bottom
# proves it rather than assuming it.
#
# The sanitizer runtimes are not listed: libasan, libubsan and libtsan come with
# g++ itself (/usr/lib/gcc/<triple>/13/), so `-fsanitize=address` works out of the
# box and naming them here would only pin what build-essential already decides.
#
# git is not incidental either - a checkout mounted into this image is asked for
# `git ls-files` (which files a format gate covers) and `git describe` (the
# firmware version), so a build without it fails in a way that looks like a
# project bug.
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential \
      cmake \
      ninja-build \
      ccache \
      pkg-config \
      libgtest-dev \
      libgmock-dev \
      git \
      ca-certificates \
      curl \
      jq \
      python3 \
      python3-venv \
    && apt-get autoremove -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ── pip: the QA toolchain, in a venv, pinned ──────────────────────────────────
#
# A venv rather than the system interpreter because Ubuntu 24.04 ships PEP 668:
# a plain `pip install` into /usr refuses with externally-managed-environment.
# Putting the venv first on PATH is what keeps `ruff`, `mypy` and `clang-tidy`
# callable by bare name, and makes `python3 -m ruff` - the form a runner script
# uses when it wants the interpreter's own copy - resolve to this one.
#
# The numbers are this repository's copy of the versions the consuming project
# pins for the same tools. They are repeated rather than fetched: an image builds
# from its own tree, and nothing here can read another repository at build time.
# The LABELs at the bottom are what let the consumer verify the two agree instead
# of assuming it.
ARG RUFF_VERSION=0.15.20
ARG MYPY_VERSION=2.1.0
ARG PYTEST_VERSION=9.1.1
ARG JSONSCHEMA_VERSION=4.26.0
ARG CLANG_FORMAT_VERSION=22.1.5
ARG CLANG_TIDY_VERSION=22.1.0
ENV VIRTUAL_ENV=/opt/qa-venv
ENV PATH="${VIRTUAL_ENV}/bin:${PATH}"
RUN python3 -m venv "${VIRTUAL_ENV}" \
    && pip install --no-cache-dir \
      "ruff==${RUFF_VERSION}" \
      "mypy==${MYPY_VERSION}" \
      "pytest==${PYTEST_VERSION}" \
      "jsonschema==${JSONSCHEMA_VERSION}" \
      "clang-format==${CLANG_FORMAT_VERSION}" \
      "clang-tidy==${CLANG_TIDY_VERSION}" \
    && pip check

# ── paho.mqtt.c, from the commit the consuming project pins ───────────────────
#
# The COMMIT, not the tag: a tag is a mutable ref, while the SHA is what makes the
# checkout reproducible - the same rule this repository already applies to the
# ESP-Matter pin. Git verifies the object against its hash, so no separate content
# check is needed.
#
# The distro package is not used, and the CMake flags are the ones the project's
# own CI action used: SSL off, because the framework links paho-mqtt3a alone and
# has no TLS backend on POSIX yet, and HIGH_PERFORMANCE on, which is paho's
# documented production mode. Building it any other way would make a test that
# passes here mean nothing about CI.
ARG PAHO_VERSION=v1.3.16
ARG PAHO_REF=4a939ddb01eea581a32fd6f0adcfee51b91d2601
ARG PAHO_REPO=https://github.com/eclipse-paho/paho.mqtt.c.git
RUN set -eu; \
    src="$(mktemp -d)"; \
    git -C "$src" init -q; \
    git -C "$src" fetch -q --depth 1 "${PAHO_REPO}" "${PAHO_REF}"; \
    git -C "$src" checkout -q FETCH_HEAD; \
    cmake -S "$src" -B "$src/build" -G Ninja \
      -DCMAKE_BUILD_TYPE=RelWithDebInfo \
      -DPAHO_BUILD_SHARED=TRUE \
      -DPAHO_WITH_SSL=FALSE \
      -DPAHO_HIGH_PERFORMANCE=TRUE \
      -DPAHO_ENABLE_TESTING=FALSE; \
    cmake --build "$src/build"; \
    cmake --install "$src/build"; \
    ldconfig; \
    rm -rf "$src"

# ── lychee, the offline markdown link checker ─────────────────────────────────
#
# A release binary with a literal checksum per architecture: the amd64 tarball is
# not the arm64 one, so a single SHA would leave one of the two legs unbuildable,
# and fetching the .sha256 from the same release would verify transfer integrity
# only - an upstream compromise rotates both files in one act. A version bump
# therefore edits all three values by hand, deliberately outside Dependabot, which
# sees neither a `curl` argument nor an ARG.
ARG LYCHEE_VERSION=v0.24.2
ARG LYCHEE_SHA256_AMD64=1f4e0ef7f6554a6ed33dd7ac144fb2e1bbed98598e7af973042fc5cd43951c9a
ARG LYCHEE_SHA256_ARM64=91a7bd65685da41b90ccb9bc867a3d649a7818042dae04ff405e55a25bddee4c
RUN set -eu; \
    case "$(dpkg --print-architecture)" in \
      amd64) triple=x86_64-unknown-linux-gnu; sha="${LYCHEE_SHA256_AMD64}" ;; \
      arm64) triple=aarch64-unknown-linux-gnu; sha="${LYCHEE_SHA256_ARM64}" ;; \
      *) echo "no lychee release for $(dpkg --print-architecture)" >&2; exit 1 ;; \
    esac; \
    art="lychee-${triple}.tar.gz"; \
    curl -sfL --proto '=https' --proto-redir '=https' \
      "https://github.com/lycheeverse/lychee/releases/download/lychee-${LYCHEE_VERSION}/${art}" -o "$art"; \
# A pipe, and a safe one: echo cannot fail, so the pipeline's status is
# sha256sum's - which is what dash gives without `set -o pipefail`, an option it
# does not have. That is the only shape a pipe may take in this file; anything
# whose left-hand side can fail (`curl … | tar -xz`, say) would go green on a
# failed download. The docker layer below carries the same pipe for the same
# reason.
    echo "${sha}  ${art}" | sha256sum -c; \
    tar -xz --strip-components=1 -f "$art" "lychee-${triple}/lychee"; \
    install -m 0755 lychee /usr/local/bin/lychee; \
    rm -f "$art" lychee

# ── the docker CLI, client only ───────────────────────────────────────────────
#
# A test suite that stands its own services up - a broker, a database - starts
# them as *sibling* containers through the host's daemon socket, mounted in by
# whoever runs this image. So the client is all that is needed here, and the
# daemon would be actively wrong: nothing in this image should be able to run one.
#
# Which is why this comes from Docker's static release rather than from apt.
# Ubuntu 24.04 has no client-only package at all (`docker-cli` does not exist;
# `docker.io` pulls in the daemon, containerd and runc), and Docker's own apt
# repository would put a third-party source and a signing key into the image
# without buying automatic updates - the label below has to name an exact version,
# so the package would be pinned there too. The static tarball carries the whole
# engine and exactly one member of it is extracted.
#
# Same shape as lychee above: a literal checksum per architecture, verified before
# anything is unpacked, and a version bump edits all three values by hand.
ARG DOCKER_VERSION=29.7.2
ARG DOCKER_SHA256_AMD64=803d433f226db4776e1768fd319fc6c6e4935a456acf84fcc0080818b854bc8f
ARG DOCKER_SHA256_ARM64=43d143448adf2c2787704e7d7704fd6d62d367a54c5edaef0a3f75509cb0938d
RUN set -eu; \
    case "$(dpkg --print-architecture)" in \
      amd64) arch=x86_64; sha="${DOCKER_SHA256_AMD64}" ;; \
      arm64) arch=aarch64; sha="${DOCKER_SHA256_ARM64}" ;; \
      *) echo "no docker static build for $(dpkg --print-architecture)" >&2; exit 1 ;; \
    esac; \
    art="docker-${DOCKER_VERSION}.tgz"; \
    curl -sfL --proto '=https' --proto-redir '=https' \
      "https://download.docker.com/linux/static/stable/${arch}/${art}" -o "$art"; \
    echo "${sha}  ${art}" | sha256sum -c; \
# One member, named explicitly: the tarball also carries dockerd, containerd and
# runc, and an unqualified extraction would install a daemon this image has no
# business carrying.
    tar -xz --strip-components=1 -f "$art" docker/docker; \
    install -m 0755 docker /usr/local/bin/docker; \
    rm -f "$art" docker

# ── running as the invoking user ──────────────────────────────────────────────
#
# The expected invocation mounts a checkout and passes `-u $(id -u):$(id -g)`, so
# the repository is owned by a uid this image knows nothing about. Without
# safe.directory git refuses it as "dubious ownership" and both `git ls-files` and
# `git describe` fail - inside the container only, which is the confusing kind of
# failure. It stays `'*'` rather than naming /workspace: safe.directory matches a
# worktree path exactly, and a consumer running this image as a job `container:`
# gets its checkout under /__w/<repo>/<repo>, which a narrowed entry would refuse.
#
# HOME is a directory of this image's own, not /tmp: that uid has no passwd entry,
# so tools would otherwise write to /, and /tmp is scratch space a caller is
# entitled to replace - `--tmpfs /tmp`, a volume mounted over it, an `rm -rf
# /tmp/*` step - which would take HOME with it mid-run. Both it and the ccache
# directory are 1777 rather than 0777: an arbitrary uid has to be able to write
# them, and the sticky bit is what keeps one uid from replacing another's files
# once it can.
RUN git config --system --add safe.directory '*'
ENV HOME=/home/build
ENV CCACHE_DIR=/opt/ccache
RUN mkdir -p "${HOME}" "${CCACHE_DIR}" && chmod 1777 "${HOME}" "${CCACHE_DIR}"

# ── the two defaults that make the tools above actually apply ─────────────────
#
# Installing ccache does not put it in the path of a build: /usr/lib/ccache ships
# `gcc` and `g++` wrappers but no `cc` or `c++`, which are the names CMake looks
# for first, so a PATH entry would leave a CMake project compiling straight
# through /usr/bin/c++ with the cache untouched. The launcher variables are read
# by CMake itself and hold whatever compiler the project picks; override with
# `-DCMAKE_CXX_COMPILER_LAUNCHER=` to build without the cache.
#
# The compile database is what clang-tidy resolves `-p <build-dir>` against, and
# CMake writes it only when asked. Setting it here is what makes the analyzer this
# image exists for work against an ordinary `cmake -S . -B build` rather than
# against a re-configure with one more flag nobody remembers.
ENV CMAKE_C_COMPILER_LAUNCHER=ccache
ENV CMAKE_CXX_COMPILER_LAUNCHER=ccache
ENV CMAKE_EXPORT_COMPILE_COMMANDS=ON

# ── the pins, machine-readable ────────────────────────────────────────────────
#
# A consumer pins its own tool versions in its own tree; these labels are what let
# it assert the image agrees, so a drift between the two repositories surfaces as
# a named test failure rather than as a gate that quietly started meaning
# something else.
LABEL org.opencontainers.image.source="https://github.com/jethome-iot/jethome-dev" \
      org.opencontainers.image.description="Host (POSIX) build, test and QA image: GCC, CMake, Ninja, GTest/GMock, paho.mqtt.c, clang-format, clang-tidy, ruff, mypy, pytest, lychee, docker CLI" \
      dev.jethome.paho.version="${PAHO_VERSION}" \
      dev.jethome.paho.ref="${PAHO_REF}" \
      dev.jethome.clang-tidy.version="${CLANG_TIDY_VERSION}" \
      dev.jethome.clang-format.version="${CLANG_FORMAT_VERSION}" \
      dev.jethome.ruff.version="${RUFF_VERSION}" \
      dev.jethome.mypy.version="${MYPY_VERSION}" \
      dev.jethome.pytest.version="${PYTEST_VERSION}" \
      dev.jethome.jsonschema.version="${JSONSCHEMA_VERSION}" \
      dev.jethome.lychee.version="${LYCHEE_VERSION}" \
      dev.jethome.docker-cli.version="${DOCKER_VERSION}"

WORKDIR /workspace

# ── verification ──────────────────────────────────────────────────────────────
#
# Every line below is an assertion, not a listing. A tool that never installed
# still leaves a green build until something asks it for its version, and a
# library that installed as a stub still links until something calls it.
#
# smoke/ is a two-file CMake project that the layer configures, builds with Ninja
# and runs under ctest. It covers what a version print cannot: that
# `find_package(GTest)` resolves, that GMock links, that libpaho-mqtt3a is found
# by name, and that the paho actually loaded reports the version this Dockerfile
# pins - the pin and the artifact disagreeing fails the build here rather than
# shipping an image that contradicts its own label. Its build tree is deleted; the
# sources stay at /opt/smoke-src, so the same check can be re-run against a
# published image (the README says how).
#
# The two clang tools assert their number instead of printing it: what pip
# installed and what the wrapper executes are two different things, and "some
# clang-tidy" is precisely the state this image exists to rule out. The docker
# client asserts for a different reason: its version is a label a consumer tests
# its own tree against, so a binary disagreeing with the label has to fail here
# rather than downstream. clang-tidy is
# then *run*, over smoke.cpp and the compile database the build just wrote,
# because a wheel whose binary cannot find its own resource directory answers
# `--version` perfectly and then fails on the first real file - the same "some
# clang-tidy", one step further along. The ccache assertion is of the same kind:
# it checks that CMake took the launcher, since a cache nothing is wired to is
# indistinguishable from a working one until someone measures a rebuild.
#
# The freeze goes to a file rather than a pipe, so the image carries its own
# snapshot and nothing can swallow a failure - and jsonschema is asserted from it
# because it is the one pin no tool here prints a version for.
#
# Nothing below pipes a tool's output anywhere, and that is deliberate rather than
# tidy: this image sets no SHELL, so these layers run under dash, which has no
# `set -o pipefail`. `gcc --version | head -1` would therefore take head's exit
# status - a missing compiler would print an error and leave the layer green,
# which is the exact failure this layer exists to catch. The assertions compare
# with `case` for the same reason.
COPY smoke/ /opt/smoke-src/
RUN set -eu; \
# The build below runs as root, and ccache creates its subdirectories with the
# creating user's ownership and umask - so a cache warmed here would leave
# /opt/ccache/tmp root-owned and every later `-u $(id -u)` run failing with
# "failed to create temporary file ... Permission denied". Disabling the cache for
# this layer keeps the directory as `mkdir` left it: empty and 1777. The launcher
# is still exercised, since ccache is what CMake invokes either way.
    CCACHE_DISABLE=1; export CCACHE_DISABLE; \
    cmake --version; \
    ninja --version; \
    gcc --version; \
    git --version; \
    jq --version; \
    ccache --version; \
    python3 --version; \
    ruff --version; \
    mypy --version; \
    pytest --version; \
    lychee --version; \
    docker --version; \
# Compared for equality, not for a substring: `*29.7.2*` also accepts 29.7.21.
# `docker version --format` prints the client's own version before it goes on to
# ask a daemon that is not here, so its non-zero exit is expected and the value is
# what matters - and an empty value (a broken binary) fails the comparison, which
# is the direction this has to fail in.
    docker_reported="$(docker version --format '{{.Client.Version}}' \
                        2>/dev/null || true)"; \
    [ "${docker_reported}" = "${DOCKER_VERSION}" ] \
      || { echo "docker reports '${docker_reported}', want ${DOCKER_VERSION}" >&2; \
           exit 1; }; \
# The promise this image makes is that it cannot run a daemon, and one member of
# that tarball is all that stands between the two. A bump reaching for a plugin
# could widen the extraction without anyone noticing, so the absence is asserted
# rather than assumed - and asserted over the filesystem rather than over PATH.
# `command -v` would answer for the search path only, while the extraction runs
# with / as its working directory: a widened `tar` drops `/dockerd`, which is not
# on PATH and would sail past the very check written to catch it. Every name the
# tarball carries is listed, not just the daemon. `-xdev` keeps the walk inside
# the image, and it costs under a second.
    for forbidden in dockerd containerd runc docker-proxy \
                     containerd-shim-runc-v2 ctr docker-init; do \
      found="$(find / -xdev -name "${forbidden}" -print -quit 2>/dev/null || true)"; \
      [ -z "${found}" ] \
        || { echo "${found} is in this image - it must carry the client only" >&2; \
             exit 1; }; \
    done; \
    clang_format_reported="$(clang-format --version)"; \
    clang_tidy_reported="$(clang-tidy --version)"; \
    echo "${clang_format_reported}"; \
    echo "${clang_tidy_reported}"; \
    case "${clang_format_reported}" in \
      *"${CLANG_FORMAT_VERSION}"*) ;; \
      *) echo "clang-format reports something other than ${CLANG_FORMAT_VERSION}" >&2; exit 1 ;; \
    esac; \
    case "${clang_tidy_reported}" in \
      *"${CLANG_TIDY_VERSION}"*) ;; \
      *) echo "clang-tidy reports something other than ${CLANG_TIDY_VERSION}" >&2; exit 1 ;; \
    esac; \
    pip freeze > /opt/qa-packages.txt; \
    grep -qx "clang-tidy==${CLANG_TIDY_VERSION}" /opt/qa-packages.txt; \
    grep -qx "clang-format==${CLANG_FORMAT_VERSION}" /opt/qa-packages.txt; \
    grep -qx "jsonschema==${JSONSCHEMA_VERSION}" /opt/qa-packages.txt; \
    cmake -S /opt/smoke-src -B /tmp/smoke-build -G Ninja \
      -DPAHO_EXPECTED_VERSION="${PAHO_VERSION}"; \
    grep -qx "CMAKE_CXX_COMPILER_LAUNCHER:STRING=ccache" /tmp/smoke-build/CMakeCache.txt; \
    cmake --build /tmp/smoke-build; \
    ctest --test-dir /tmp/smoke-build --output-on-failure; \
# Real analysis over a real file: `--checks=-*` alone exits 0 whatever happens,
# so the check set is what makes a compilation error - a missing resource
# directory, an unusable system header - fail this layer.
    clang-tidy --quiet "--checks=-*,bugprone-*" -p /tmp/smoke-build /opt/smoke-src/smoke.cpp; \
    rm -rf /tmp/smoke-build; \
    echo "jethome host image verified"

CMD ["/bin/bash"]
