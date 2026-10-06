# JetHome host development image
#
# Builds and tests the POSIX target of a C++ firmware project on the machine it
# runs on, and carries the QA gates that project runs beside the build: ruff,
# mypy, pytest, clang-format, clang-tidy and lychee, plus Node.js with corepack
# for the gate of a web frontend living in the same tree. It also carries the
# Docker client — no daemon — so a suite that stands its own services up can do
# it through a socket the caller mounts.
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
# A toolchain and nothing a build links beyond the standard library: no test
# framework, no third-party C/C++ library. A project consuming this image fetches
# those at its own pins, and a system copy here would be a trap rather than a
# convenience - a stray `find_package` or `find_library` in that project would pick
# it up silently instead of failing, which is how a consumer's GoogleTest once
# drifted from its pin. GTest, GMock and paho.mqtt.c lived here until their one
# consumer stopped taking them from the machine.
#
# GCC's sanitizer runtimes are not listed: libasan, libubsan and libtsan come with
# g++ itself (/usr/lib/gcc/<triple>/13/), so `g++ -fsanitize=address` works out of
# the box and naming them here would only pin what build-essential already
# decides. clang's are a different package entirely - see the layer below.
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
      git \
      ca-certificates \
      curl \
      jq \
      python3 \
      python3-venv \
    && apt-get autoremove -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ── clang, for a second AddressSanitizer ──────────────────────────────────────
#
# Not a second build toolchain: GCC stays what `cc` and `c++` resolve to, and
# clang is reached only by its versioned name. It is here for one class of bug
# GCC's ASan cannot see. GCC keeps every local of a function's outermost block
# alive until the block ends - including while the destructors of objects declared
# *earlier* run, by which time C++ has already ended those locals' lifetimes.
# clang poisons each variable when its own lifetime ends, so a callback reading a
# dead local from a destructor is `stack-use-after-scope` under clang and a clean
# run under GCC, `-fsanitize-address-use-after-scope` or not. smoke/use-after-scope.cpp
# is that case in a dozen lines, and smoke/verify-clang.sh, which the verification
# layer runs, asserts clang catches it.
#
# Three packages, each for a reason:
#   clang-N            the compiler. It links this image's libstdc++ - no libc++
#                      is installed - so a clang-built leg differs from the GCC
#                      one in the compiler alone;
#   libclang-rt-N-dev  compiler-rt, i.e. clang's ASan runtime. It is not GCC's
#                      libasan and has to match the compiler's own version;
#   llvm-N             for llvm-symbolizer; without it a report is raw addresses.
#
# From the base archive, with no extra apt source, so the default names the major
# the archive of UBUNTU_BASE_TAG carries - 18 for 24.04. Nothing moves it for you:
# a base bump edits this default by hand, in the same change. Forgetting fails
# loudly where the new archive has no clang-18, and quietly where it still carries
# one beside a newer default - the build then passes on the old major, which is
# why the bump is named here. CLANG_VERSION is a major and nothing finer - the
# point release is apt's to choose (see ./scripts/check-pins.sh on why apt goes
# unpinned), and the label below is built from this ARG, so it names the major
# too: a LABEL cannot read what apt resolved at build time.
ARG CLANG_VERSION=18
RUN apt-get update && apt-get install -y --no-install-recommends \
      clang-${CLANG_VERSION} \
      libclang-rt-${CLANG_VERSION}-dev \
      llvm-${CLANG_VERSION} \
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
#
# pytest-xdist is pytest's plugin for running one suite in several worker
# processes. It sits beside pytest because the consumer's tooling suite is long
# enough that a single process on a shared runner can run out of its job's time
# limit (jethome-iot/jetcontrol-cpp#1489).
ARG RUFF_VERSION=0.16.5
ARG MYPY_VERSION=2.3.1
ARG PYTEST_VERSION=9.1.1
ARG PYTEST_XDIST_VERSION=3.8.0
ARG JSONSCHEMA_VERSION=4.26.0
ARG CLANG_FORMAT_VERSION=23.1.0
ARG CLANG_TIDY_VERSION=22.1.8
ENV VIRTUAL_ENV=/opt/qa-venv
ENV PATH="${VIRTUAL_ENV}/bin:${PATH}"
RUN python3 -m venv "${VIRTUAL_ENV}" \
    && pip install --no-cache-dir \
      "ruff==${RUFF_VERSION}" \
      "mypy==${MYPY_VERSION}" \
      "pytest==${PYTEST_VERSION}" \
      "pytest-xdist==${PYTEST_XDIST_VERSION}" \
      "jsonschema==${JSONSCHEMA_VERSION}" \
      "clang-format==${CLANG_FORMAT_VERSION}" \
      "clang-tidy==${CLANG_TIDY_VERSION}" \
    && pip check

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
# failed download. The docker and Node layers below carry the same pipe for the
# same reason.
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

# ── Node.js, for a web frontend's gate ────────────────────────────────────────
#
# A consumer whose tree carries a frontend (Vite, TypeScript, pnpm) runs its QA
# gate - a frozen-lockfile install, lint, typecheck, the build - beside the C++
# ones. With no Node here that gate either is skipped locally or runs on a bare CI
# runner through actions/setup-node, which is a second description of the one
# environment this image exists to be.
#
# From Node's own release tarball, in the shape of lychee and docker above: a
# literal checksum per architecture, verified before anything is unpacked, and a
# bump edits all three values by hand. Node does publish a SHASUMS256.txt beside
# the tarballs, and it is signed - the two sums here were copied out of it after
# its signature checked out against the Node release keys. Fetching it at build
# time instead would verify the transfer only, for the reason given at lychee.
# Not from apt: the 24.04 archive does not carry the LTS line a consumer pins. Not
# from NodeSource either, which is an apt source and a signing key more to keep in
# step. The .gz rather than the .xz, because gzip is in the base and xz-utils is
# not.
#
# NODE_VERSION carries no leading `v`, so the label below reads exactly as a
# consumer's .nvmrc does; the URL and the verification layer add the `v`.
#
# Node 24 is the last line that bundles corepack - from 25 on it is a separate
# package, so a bump past 24 installs it explicitly, pinned. The verification
# layer fails such a bump that forgets, rather than publishing an image whose
# `pnpm` resolves to nothing.
ARG NODE_VERSION=24.21.0
ARG NODE_SHA256_AMD64=6e1db87ef58b8819e5d5402eff1536491b18edd8eb7bee5ef7897876e88dc5ff
ARG NODE_SHA256_ARM64=724282c3b43aec998aa9527380465b45d229e021b58035f5f4f63095eabfe5d5
# An ARG, not an ENV, for DEBIAN_FRONTEND's reason: every RUN from here on sees
# it, and no shell the user opens later does. corepack turns on Node's module
# compile cache, which lands in /tmp/node-compile-cache - root-owned when a build
# layer writes it, and so read-only to every `-u $(id -u)` run after. The
# verification layer checks that /tmp leaves the build empty.
ARG NODE_DISABLE_COMPILE_CACHE=1
RUN set -eu; \
    case "$(dpkg --print-architecture)" in \
      amd64) arch=x64; sha="${NODE_SHA256_AMD64}" ;; \
      arm64) arch=arm64; sha="${NODE_SHA256_ARM64}" ;; \
      *) echo "no Node.js release for $(dpkg --print-architecture)" >&2; exit 1 ;; \
    esac; \
    dir="node-v${NODE_VERSION}-linux-${arch}"; \
    art="${dir}.tar.gz"; \
    curl -sfL --proto '=https' --proto-redir '=https' \
      "https://nodejs.org/dist/v${NODE_VERSION}/${art}" -o "$art"; \
    echo "${sha}  ${art}" | sha256sum -c; \
# Into /usr/local, so node, npm, npx and corepack resolve by bare name. The
# members are named because the tarball's root also holds a README and a
# CHANGELOG, which --strip-components would drop loose into /usr/local; the
# LICENSE is taken in the same pass and moved beside the docs Node ships under
# share/. include/ is left out: those are the headers a native addon compiles
# against, and node-gyp never reads them from here - this build of Node does not
# look for headers under its prefix (use_prefix_to_find_headers is false), so
# node-gyp downloads its own copy - which would leave 64 MB nobody opens.
# --no-same-owner because tar running as root restores the archive's own uid -
# 1001, the release builder's - and not only on the files it creates: measured,
# /usr/local/bin and /usr/local/lib themselves come out 1001-owned, so a caller
# running this image as `-u 1001` could replace every binary in them.
    tar -xz --strip-components=1 --no-same-owner -C /usr/local -f "$art" \
      "${dir}/bin" "${dir}/lib" "${dir}/share" "${dir}/LICENSE"; \
    mv /usr/local/LICENSE /usr/local/share/doc/node/LICENSE; \
    rm -f "$art"; \
# corepack, not pnpm. `corepack enable` puts pnpm and yarn shims beside node, and
# each runs the version the project's own `packageManager` field names, checking
# the hash that field carries when it downloads that version - a version already
# in the cache is not checked again. So the image holds no package-manager
# version of its own to fall out of step with a consumer's: the project picks
# it, and its first run downloads it into the corepack cache under $HOME. Yarn 2
# and later goes one step further on its own: a `yarnPath` in the project's
# .yarnrc.yml hands over to a file the checkout ships, which nothing here checks.
    corepack enable

# The shims ask before that first download - `pnpm` sets
# COREPACK_ENABLE_DOWNLOAD_PROMPT=1 unless the environment already did - and the
# question waits on stdin when stdin is a terminal and CI is unset: `docker run
# -it`, not a CI job, so it never stood between a CI run and a download. It is
# switched off. What it would ask about is the version packageManager names, or,
# for a project naming none, the release corepack picks - the drift the README
# warns about, and which the question never stopped in CI either.
#
# What the question did stand in front of, in a terminal, is a checkout steering
# corepack itself. corepack reads a .corepack.env beside the package.json and
# takes every COREPACK_* key in it that the environment does not set: a URL in
# packageManager allowed through COREPACK_ENABLE_UNSAFE_CUSTOM_URLS=1, another
# registry with COREPACK_NPM_REGISTRY and signature checks off with
# COREPACK_INTEGRITY_KEYS=0, or a COREPACK_HOME pointing into the checkout at a
# "cached" pnpm it ships itself, which runs with no download and no hash check at
# all. Measured with the first: `pnpm --version` fetched a URL's code and ran it
# without a word. So corepack is told not to read that file - COREPACK_ENV_FILE=0,
# which the file cannot override, as the process environment wins over it. What
# corepack does is then decided by packageManager and by the caller, who passes
# any COREPACK_* setting the project needs with `-e`. That does not make an
# untrusted checkout safe to build - `pnpm install` and `pnpm run` execute the
# project's own scripts - it keeps `pnpm` meaning the release packageManager
# names.
ENV COREPACK_ENABLE_DOWNLOAD_PROMPT=0
ENV COREPACK_ENV_FILE=0

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
#
# `image.version` is among them because a LABEL is inherited through FROM: ubuntu
# sets it to `24.04`, so every published host image announced itself as version
# 24.04 until this line existed - the base's version, not this image's. It is
# assembled from the same ARG the variant's tag is checked against, so a version
# bump cannot move one without the other - though check-versions.sh matches the
# tag on a token boundary rather than for equality, so the two would differ under
# a tag carrying more than the version. The manifest job annotates the published
# index with the same field, taking the tag verbatim; annotations are not
# inherited at all, and these labels are what an image already pulled reports and
# what a local ./scripts/build.sh produces.

# Re-declared after FROM: an ARG stated before it is out of scope below, so the
# label would expand to the empty string - silently, since Docker does not object
# to an undefined variable.
ARG UBUNTU_BASE_TAG

LABEL org.opencontainers.image.source="https://github.com/jethome-iot/jethome-dev" \
      org.opencontainers.image.description="Host (POSIX) build, test and QA image: GCC, clang with its ASan runtime, CMake, Ninja, clang-format, clang-tidy, ruff, mypy, pytest with pytest-xdist, lychee, docker CLI, Node.js with corepack" \
      org.opencontainers.image.version="ubuntu-${UBUNTU_BASE_TAG}" \
      org.opencontainers.image.base.name="ubuntu:${UBUNTU_BASE_TAG}" \
      dev.jethome.clang.version="${CLANG_VERSION}" \
      dev.jethome.clang-tidy.version="${CLANG_TIDY_VERSION}" \
      dev.jethome.clang-format.version="${CLANG_FORMAT_VERSION}" \
      dev.jethome.ruff.version="${RUFF_VERSION}" \
      dev.jethome.mypy.version="${MYPY_VERSION}" \
      dev.jethome.pytest.version="${PYTEST_VERSION}" \
      dev.jethome.pytest-xdist.version="${PYTEST_XDIST_VERSION}" \
      dev.jethome.jsonschema.version="${JSONSCHEMA_VERSION}" \
      dev.jethome.lychee.version="${LYCHEE_VERSION}" \
      dev.jethome.docker-cli.version="${DOCKER_VERSION}" \
      dev.jethome.node.version="${NODE_VERSION}"

WORKDIR /workspace

# ── verification ──────────────────────────────────────────────────────────────
#
# Every line below is an assertion, not a listing. A tool that never installed
# still leaves a green build until something asks it for its version, and a
# toolchain that answers `--version` can still fail on the first real file.
#
# smoke/verify.sh covers what a version print cannot, with a small CMake project
# beside it - what it checks and why is in its own comments, kept there because the
# README runs the same script against a published image. Its build tree is
# deleted; the sources stay at /opt/smoke-src. Beside them sits verify-clang.sh,
# which builds use-after-scope.cpp - not part of that project - and requires it to
# *fail*; see the clang block at the end.
#
# The two clang tools assert their number instead of printing it: what pip
# installed and what the wrapper executes are two different things, and "some
# clang-tidy" is precisely the state this image exists to rule out. The docker
# client and node assert for a different reason: each version is a label a
# consumer tests its own tree against, so a binary disagreeing with its label has
# to fail here rather than downstream. verify.sh then *runs* clang-tidy, the same
# "some clang-tidy" one step further along.
#
# The freeze goes to a file rather than a pipe, so the image carries its own
# snapshot and nothing can swallow a failure - and jsonschema and pytest-xdist are
# asserted from it because they are the pins no tool here prints a version for.
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
# is still exercised, since ccache is what CMake invokes either way. Node's
# compile cache is off for the same reason, through the ARG at the Node layer.
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
# Equality again, and against the `v` Node prints and the ARG leaves out.
    node_reported="$(node --version)"; \
    echo "node ${node_reported}"; \
    [ "${node_reported}" = "v${NODE_VERSION}" ] \
      || { echo "node reports '${node_reported}', want v${NODE_VERSION}" >&2; exit 1; }; \
    npm --version; \
    corepack --version; \
# `corepack enable` is what makes `pnpm` resolve at all, and it is a step of its
# own that a bump can lose - past Node 24, where corepack stops coming with the
# tarball, most easily. The shim has to be corepack's, not some other pnpm earlier
# on PATH. It is not *run*: that would download a pnpm, whose version is the
# project's to name, into a HOME this root-run layer must leave untouched (see
# the end of this layer). `|| true` so a missing shim reaches the message below
# instead of ending the layer at the assignment with a bare status 127.
    pnpm_shim="$(command -v pnpm || true)"; \
    [ "$(readlink -f "${pnpm_shim}")" = /usr/local/lib/node_modules/corepack/dist/pnpm.js ] \
      || { echo "pnpm resolves to '${pnpm_shim}', not to corepack's shim" >&2; exit 1; }; \
# COREPACK_ENV_FILE=0 is a promise that a checkout's .corepack.env is not read,
# and nothing else in this layer would notice it being broken - by a corepack
# bump renaming the switch, say. So a checkout whose .corepack.env re-enables
# custom URLs is staged here, and its packageManager URL must be refused, which
# happens only while the file goes unread. Offline: corepack refuses before it
# fetches anything, and one that read the file fails the grep instead, on a host
# that does not resolve.
    probe="$(mktemp -d)"; \
    echo '{"packageManager":"pnpm@https://example.invalid/pm.js"}' > "${probe}/package.json"; \
    echo 'COREPACK_ENABLE_UNSAFE_CUSTOM_URLS=1' > "${probe}/.corepack.env"; \
    if (cd "${probe}" && pnpm --version) > "${probe}/out.txt" 2>&1; then \
      cat "${probe}/out.txt"; \
      echo "pnpm ran a packageManager URL a .corepack.env enabled" >&2; exit 1; \
    fi; \
    grep -q 'Illegal use of URL for known package manager' "${probe}/out.txt" \
      || { cat "${probe}/out.txt"; \
           echo "pnpm failed on a packageManager URL, but not by refusing it" >&2; \
           exit 1; }; \
    rm -rf "${probe}"; \
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
    grep -qx "pytest-xdist==${PYTEST_XDIST_VERSION}" /opt/qa-packages.txt; \
    sh /opt/smoke-src/verify.sh /tmp/smoke-build; \
    rm -rf /tmp/smoke-build; \
# clang is asserted by what it catches - its ASan has to report the use-after-scope
# GCC's misses, symbolized - and its leg is kept comparable with the GCC one.
# smoke/verify-clang.sh holds all of it and says why, for the reason verify.sh
# holds the smoke check: the README runs the same file against a published image.
    sh /opt/smoke-src/verify-clang.sh "${CLANG_VERSION}"; \
# HOME and /tmp leave this layer as empty as they came, for the reason the ccache
# directory does: the layer runs as root, and whatever a tool caches there here -
# npm's logs, corepack's downloads, Node's compile cache - would be root's in
# every later `-u $(id -u)` run, which could neither write into it nor, under the
# sticky bit, replace it.
    for scratch in "${HOME}" /tmp; do \
      left="$(ls -A "${scratch}")"; \
      [ -z "${left}" ] \
        || { echo "the build left files in ${scratch}: ${left}" >&2; exit 1; }; \
    done; \
    echo "jethome host image verified"

CMD ["/bin/bash"]
