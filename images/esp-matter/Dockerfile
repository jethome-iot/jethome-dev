# ESP-Matter Development Image
# Based on https://docs.espressif.com/projects/esp-matter/en/latest/esp32/developing.html

# One argument carries the whole reference so CI can pass a digest
# (…/jethome-dev-esp-idf@sha256:…), which a tag-shaped ARG cannot express - the
# separator differs. CI pins the exact esp-idf image its own run produced; the
# default below is what a local ./scripts/build.sh uses, and it also makes the
# owner overridable instead of hardcoded, so a fork can build against its own base.
ARG BASE_IMAGE=ghcr.io/jethome-iot/jethome-dev-esp-idf:idf-v5.5.5
# The Matter specification this image carries. Descriptive only - what actually
# gets checked out is ESP_MATTER_REF below.
ARG ESP_MATTER_VERSION=v1.6
# The exact upstream commit. ESP-Matter publishes no git tags, only moving
# release/* branches, so a branch name identifies a line rather than a release:
# release/v1.5 carried specification v1.5 at one commit and v1.5.1 at another.
# Pinning the commit is what makes an image tag mean something - and what makes a
# rebuild reproduce the same tree instead of picking up whatever landed upstream.
# Update with ./scripts/update-matter-ref.sh.
ARG ESP_MATTER_REF=2c125619610b9a16bb8e92f5ebbf55111638615e
# The ESP-IDF version underneath, for the label and - the actual reason it is an
# arg - for the assertion. The label alone would need nothing: Docker inherits a
# base image's LABELs, so building on this repository's esp-idf already carries
# `dev.jethome.idf.version` down. What inheritance cannot do is *check* it, and it
# carries nothing at all when BASE_IMAGE points at some other image. Since CI
# passes that base as a digest, and a digest names no version, the value comes
# from images/versions.json instead - taken there from the same `base_tag` the
# digest was resolved from, with the checker refusing a value the variant's own
# tag does not name.
ARG IDF_VERSION=v5.5.5

FROM ${BASE_IMAGE}

# Re-declare build arguments after FROM
ARG ESP_MATTER_VERSION
ARG ESP_MATTER_REF
ARG IDF_VERSION

# Use bash for all RUN commands: the layers below call the bash builtin `source`,
# which /bin/sh does not have. (This once said "needed for QEMU emulation
# compatibility" - CI no longer emulates anything, but the reason above always was
# the real one.)
SHELL ["/bin/bash", "-c"]

# Install only Matter-specific development packages not in base image
# Base image already has: ninja-build, python3-venv, python3-pip, runtime libs
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    # Python development headers (needed for psutil and other C extensions)
    python3-dev \
    # Matter SDK build dependencies (development headers)
    pkg-config \
    libssl-dev \
    libdbus-1-dev \
    libglib2.0-dev \
    libavahi-client-dev \
    # Clean up
    && apt-get autoremove -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Fetch the pinned commit rather than cloning a branch. GitHub serves a shallow
# fetch of an arbitrary SHA, so this stays as cheap as `clone --depth 1` while
# being reproducible. Submodules need no pinning of their own: their commits are
# recorded in this tree, so fixing the superproject fixes all of it.
#
# `--platform esp32`, without the `linux` upstream documents beside it. That pair
# is the recipe for a host-tools build - "the modules for platform linux or darwin
# are required for the host tools building" (esp-matter docs/en/developing.rst) -
# and this image installs with `--no-host-tool`. Asking for `linux` here checks out
# eleven submodules nothing in this image can build against (perfetto, ot-br-posix,
# abseil-cpp, fuzztest, googletest, libdatachannel, libwebsockets, imgui, cirque,
# ot-commissioner, imx-secure-enclave) and drags in three more that connectedhomeip's
# own .gitmodules marks `excluded-platforms = esp32` (mbedtls, boringssl, lwip):
# 1.9 GB of tree and .git against 649 MB for esp32 alone. The platform names are
# upstream metadata, not a guess - checkout_submodules.py reads them from
# .gitmodules and validates them against ALL_PLATFORMS.
WORKDIR /opt
RUN git init esp-matter && \
    cd esp-matter && \
    git remote add origin https://github.com/espressif/esp-matter.git && \
    git fetch --depth 1 origin ${ESP_MATTER_REF} && \
    git checkout FETCH_HEAD && \
    git submodule update --init --depth 1 && \
    cd connectedhomeip/connectedhomeip && \
    ./scripts/checkout_submodules.py --platform esp32 --shallow

# The checkout above belongs to root, because the build created it, while the
# documented invocation runs this image as the caller's uid (`-u $(id -u):$(id -g)`,
# which is how build output in a bind-mounted workspace stays owned by the caller).
# Git then refuses the repository as "dubious ownership" - inside the container
# only, on a tree the image built itself. The base image already marks $IDF_PATH
# the same way, which is why ESP-IDF and ESP-Matter answered differently to the
# same `git -C … rev-parse HEAD`; this closes that asymmetry.
#
# Named paths rather than `*`, as upstream does. Be precise about what that buys:
# `safe.directory` matches a *path*, with no notion of who owns it, so this does
# not verify provenance - a caller who bind-mounts their own repository over
# /opt/esp-matter gets it trusted too. What the choice does buy is that everything
# *else* in the container stays subject to the ownership check, which `*` would
# switch off wholesale. The caller is the trust boundary either way.
#
# Two entries, because git checks ownership per repository and a submodule is its
# own: connectedhomeip brings dozens of nested ones, far too many to list. The
# `/*` suffix covers exactly those, and it is version-dependent - verified as
# ignored by git 2.43 (which this base ships) and honoured by 2.47, where it
# matches subdirectories but not the parent, hence both lines. On today's base the
# second line is inert and harmless; it starts working when the base's git catches
# up, and until then a reader that needs a submodule passes
# `-c safe.directory=<path>` for it.
RUN git config --system --add safe.directory /opt/esp-matter && \
    git config --system --add safe.directory '/opt/esp-matter/*'

# Answers "what is actually in here" without starting the container.
LABEL org.opencontainers.image.revision="${ESP_MATTER_REF}" \
      org.opencontainers.image.version="${ESP_MATTER_VERSION}" \
      dev.jethome.idf.version="${IDF_VERSION}"

# Install ESP-Matter (without host tools to reduce image size)
# Source ESP-IDF environment first to activate Python venv with pip
# TODO: Consider enabling host tools (chip-tool, chip-cert) in future if needed
#
# Two environment variables and a deletion list, because `install.sh` provisions a
# pigweed environment for *host* development of connectedhomeip and this image only
# ever cross-compiles for ESP32. Measured on the published idf-v5.4.1-matter-v1.4.2
# image: this layer was 6.63 GB unpacked, 3.1 GB as a blob - the single layer a
# `docker pull` stalls on.
#
# PW_NO_CIPD_CACHE_DIR: pigweed keeps every CIPD package twice - unpacked under
# .environment/cipd/packages/ and, as downloaded, in CIPD_CACHE_DIR, which defaults
# to ~/.cipd-cache-dir (pw_env_setup/py/pw_env_setup/env_setup.py). One RUN writes
# both, so both land in the layer: 1.4 GB of exact duplicate. The variable is
# upstream's own off switch, but it is not the guarantee - a renamed variable would
# fail silently, and what keeps the duplicate out of the image either way is the
# `rm -rf /root/.cipd-cache-dir` at the end of this RUN. Do not drop it as redundant;
# the variable only saves the disk during the build. PIP_NO_CACHE_DIR does the same
# for ~/.cache/pip.
#
# XDG_CACHE_HOME points the rest of the build's caches - pip-tools' wheel cache and
# zap's package cache, 24 MB between them - somewhere this RUN can delete wholesale,
# instead of leaving them under /root where a literal deletion list would have to
# name them and would go stale the moment a tool adds another one.
#
# The deletions run in this RUN so the bytes never enter the layer at all; a later
# layer removing them would only add a whiteout. What a firmware build takes out of
# this environment is `gn`, which the chip component resolves with
# `find_program(GN_EXECUTABLE gn)`; `ninja` comes from the base's apt package,
# which sits earlier on PATH than the copies kept here, and the compiler comes from
# ESP-IDF, since config/esp32/components/chip/CMakeLists.txt passes
# esp32_cc=${CMAKE_C_COMPILER}, i.e. xtensa-gcc. What goes, and why it is not
# load-bearing:
#   cipd/packages/arm       1.2 GB  arm-none-eabi-gcc 12.2, plus a cipd cpython3 that
#                                   nothing uses - pigweed-venv/pyvenv.cfg records
#                                   ESP-IDF's own interpreter as the venv's base
#   packages/pigweed/lib    985 MB  clang runtime and fuchsia sysroots
#   packages/pigweed/bin    849 MB  clang/llvm/lld (692 MB) and qemu (157 MB)
#   .../clang_sysroot       418 MB  bionic, for Android host builds
#   .../share               317 MB  qemu firmware blobs
#   gn_out                  244 MB  the venv bootstrap's own gn build output
#   .../include              22 MB  clang and libc++ headers - all but include/google
#   .../openocd, bin/openocd 8.6 MB an ARM/Fuchsia openocd that cannot reach an ESP32
#                                   and is shadowed anyway: `command -v openocd` in
#                                   this image answers ESP-IDF's openocd-esp32
#   .../libexec, .../distro-info    clang's scan-build helpers, and lsb release data
#
# Kept: `gn` and `ninja` at the package root, `bin/ninja`, `bin/protoc` together with
# `include/google` - 172 KB of well-known protos that protoc's own imports resolve
# against, so a CONFIG_ENABLE_PW_RPC build whose .proto files `import
# "google/protobuf/descriptor.proto"` still compiles - plus packages/zap and
# pigweed-venv.
#
# `bin/clang-format` stays with them, at 4.2 MB, because ZAP shells out to a
# clang-format on PATH when it regenerates C/C++ and carries no copy of its own -
# and this one is standalone rather than a front end for the toolchain deleted
# around it (`ldd` names only libc, libm, libpthread, librt and libdl). Note what
# keeping it does *not* do: `export.sh` puts the package root on PATH and not its
# `bin`, so nothing here answers to `clang-format` until a caller sources
# .environment/activate.sh, which prepends both. Keeping the binary is what makes
# that one step enough.
#
# The five paths worth hundreds of MB are asserted before they are removed. `rm -rf`
# on a path that is not there exits 0, and these are literal paths in a tree upstream
# rearranges at will: a renamed directory would leave the image quietly hundreds of MB
# heavier with every check still green. The assertion is a size guard and is scoped
# like one - libexec, distro-info and openocd are a few MB each and go unasserted,
# because which CIPD packages land in this prefix varies by platform manifest and a
# per-file inventory taken on one architecture must not fail the build on the other.
# The two `find` calls are fail-closed for their own directories - find exits non-zero
# on a missing starting point - and `find ... -exec rm -rf {} +` rather than
# `ls | grep | xargs` survives a filename hadolint's SC2010 is warning about.
#
# Deleting rather than not installing is deliberate - install.sh then runs exactly
# as upstream wrote it. To get the full environment back inside a container, remove
# .environment and re-run `./install.sh --no-host-tool`, which bootstraps from
# scratch the way this layer did. The flag is not optional there: install.sh
# defaults to building chip-tool, which needs third_party/libwebsockets, one of the
# linux-platform submodules the checkout above no longer takes. Re-running
# bootstrap.sh over the pruned tree is not the same thing either (it has to be
# sourced, and cipd reconciles against its own record of what it deployed rather
# than against the files on disk). Verified by building examples/light for esp32 in
# the resulting image, and light.bin still links.
WORKDIR /opt/esp-matter
RUN export PW_NO_CIPD_CACHE_DIR=1 PIP_NO_CACHE_DIR=1 XDG_CACHE_HOME=/tmp/build-cache && \
    source ${IDF_PATH}/export.sh && \
    ./install.sh --no-host-tool && \
    CHIP_ENV=/opt/esp-matter/connectedhomeip/connectedhomeip/.environment && \
    PW_PKG="${CHIP_ENV}/cipd/packages/pigweed" && \
    for stale in "${CHIP_ENV}/gn_out" "${CHIP_ENV}/cipd/packages/arm" \
                 "${PW_PKG}/lib" "${PW_PKG}/share" "${PW_PKG}/clang_sysroot"; do \
      [ -e "${stale}" ] \
        || { echo "nothing at ${stale} - upstream moved it, and this layer would keep it" >&2; \
             exit 1; }; \
      rm -rf "${stale}"; \
    done && \
    rm -rf "${PW_PKG}/libexec" "${PW_PKG}/distro-info" "${PW_PKG}/openocd" && \
    find "${PW_PKG}/bin" -mindepth 1 -maxdepth 1 \
         ! -name protoc ! -name ninja ! -name clang-format -exec rm -rf {} + && \
    find "${PW_PKG}/include" -mindepth 1 -maxdepth 1 \
         ! -name google -exec rm -rf {} + && \
    rm -rf /root/.cipd-cache-dir /tmp/build-cache

# Set ESP-Matter environment variables
ENV ESP_MATTER_PATH=/opt/esp-matter

# Copy and set up custom entrypoint
COPY entrypoint.sh /opt/esp/esp_matter_entrypoint.sh
RUN chmod +x /opt/esp/esp_matter_entrypoint.sh

# Set working directory
WORKDIR /workspace

# Verify installation
#
# The freeze is regenerated here, not inherited. install.sh above resolves
# esp-matter's own requirements into the same ESP-IDF venv the base image pinned,
# so the snapshot the base wrote describes an environment that no longer exists -
# and the esp-idf README points readers at this very file.
#
# esptool is asserted, not merely printed: install.sh is free to move it, and
# `idf.py flash` runs whatever the venv holds. The expected version is read out of
# the base's own snapshot *before* that file is overwritten, so this image asserts
# "install.sh did not move esptool" without repeating a version number the base
# already owns. A base with no snapshot (a fork, or an older esp-idf) skips the
# assertion rather than failing on it.
#
# The survivors of the pruning above are asserted here. The deletion list is a set
# of literal paths that upstream is free to rearrange: a renamed subdirectory would
# silently take a needed binary with it, and nothing else in this build would
# notice - a firmware build is the consumer, and it happens in someone else's CI.
# `gn` and `zap-cli` resolve through PATH and ZAP_INSTALL_PATH, so this checks what
# a caller actually gets rather than that a file exists somewhere.
#
# protoc is checked by running it, not by printing a version: it needs the
# well-known protos beside it, and `bin/protoc` surviving while `include/google`
# did not is a working binary that fails only later, in a pw_rpc build in another
# repository. It is addressed absolutely, because only the package root and not its
# `bin` is on PATH under this entrypoint - and spelled out of `ESP_MATTER_PATH`
# rather than the `_PW_ACTUAL_ENVIRONMENT_ROOT` that would read better: that
# variable is exported by esp-matter's export.sh only from v1.5.1 on, and this one
# Dockerfile also builds the pinned v1.4.2 variant, where it is empty. The path
# would have collapsed to /cipd/packages/pigweed/bin/protoc and failed that leg
# alone - in CI, on a variant no local build of the primary tag exercises.
#
# The compile is preceded by a plain existence test on the .proto it imports, and
# the two are not redundant. The compile is the behavioural half: it resolves the
# import the way a pw_rpc build does, through protoc's own implicit `../include`,
# and it was measured to fail (`File not found`) with include/google moved aside.
# Passing `--proto_path` at that directory would take the implicit lookup out of the
# test rather than strengthen it. What the file test adds is the one case the
# compile cannot see - a future protoc that carries the well-known protos inside
# itself would compile this happily with the directory gone.
#
# Both probes are given a scratch HOME and XDG_CACHE_HOME: zap is an Electron
# application and writes ~4.5 MB of cache on any invocation, `--version` included,
# which would otherwise be this layer's whole content.
#
# ZAP_INSTALL_PATH is checked for emptiness first. It comes out of the same upstream
# export.sh that turned out not to export _PW_ACTUAL_ENVIRONMENT_ROOT on the v1.4.2
# pin; every variant published today does set this one, but unset it would collapse
# to `/zap-cli` and fail a CI leg with "No such file or directory" naming a path in
# the root - a message that sends the reader looking for the wrong thing.
RUN source ${IDF_PATH}/export.sh && \
    source ${ESP_MATTER_PATH}/export.sh && \
    python --version && \
    esptool version && \
    gn --version && \
    { [ -n "${ZAP_INSTALL_PATH}" ] \
      || { echo "export.sh did not set ZAP_INSTALL_PATH" >&2; exit 1; }; } && \
    XDG_CACHE_HOME=/tmp/probe HOME=/tmp/probe \
      "${ZAP_INSTALL_PATH}/zap-cli" --version && \
    pw_pkg="${ESP_MATTER_PATH}/connectedhomeip/connectedhomeip/.environment/cipd/packages/pigweed" && \
    "${pw_pkg}/bin/protoc" --version && \
    [ -f "${pw_pkg}/include/google/protobuf/descriptor.proto" ] && \
    printf 'syntax = "proto3";\nimport "google/protobuf/descriptor.proto";\n' \
      > /tmp/probe.proto && \
    "${pw_pkg}/bin/protoc" --proto_path=/tmp --descriptor_set_out=/dev/null \
      /tmp/probe.proto && \
    rm -rf /tmp/probe /tmp/probe.proto && \
    base_esptool="$(grep -m1 '^esptool==' /opt/esp/python-packages.txt || true)" && \
    pip freeze > /opt/esp/python-packages.txt && \
    { [ -z "${base_esptool}" ] && echo "no base snapshot - esptool not asserted" \
      || grep -qx "${base_esptool}" /opt/esp/python-packages.txt; } && \
    grep -E '^(pytest|esptool)' /opt/esp/python-packages.txt && \
    idf_reported="$(idf.py --version)" && \
    echo "${idf_reported}" && \
# The inherited SDK, held to the version this image labels. IDF_VERSION arrives as
# a build arg because BASE_IMAGE is a digest and says nothing about the version -
# so without this the label would be the one thing here nobody checks.
    { [ "${idf_reported}" = "ESP-IDF ${IDF_VERSION}" ] \
      || { echo "expected 'ESP-IDF ${IDF_VERSION}', got '${idf_reported}'" >&2; \
           exit 1; }; } && \
# The safe.directory entries, asserted rather than assumed: the build runs as root,
# so nothing else here would notice their absence - which is exactly how the gap in
# this image survived until a consumer running under `-u` hit it. Each grep is
# fail-closed (an empty `git config` output fails it).
    git config --system --get-all safe.directory | grep -qx /opt/esp-matter && \
    git config --system --get-all safe.directory | grep -qFx '/opt/esp-matter/*' && \
# And the *absence* of a blanket entry, which is the half a positive check cannot
# see: the base image is overridable and pinned by digest, so a fork's base - or a
# future espressif/idf - adding `safe.directory = *` would leave every repository
# trusted while this file and the README claim otherwise. Today's upstream adds
# `$IDF_PATH` alone (checked), so this asserts a property rather than guessing one.
# `if`, not `grep && { … } || true`: that form is correct (a brace group is not a
# subshell, so `exit` leaves the layer rather than being caught by `||`) but reads
# as though the `|| true` neutralised it. Same behaviour, one obvious reading.
    { if git config --system --get-all safe.directory | grep -qFx '*'; then \
        echo "a blanket safe.directory '*' is set - this image claims path scoping" >&2; \
        exit 1; \
      fi; } && \
# Then the effect, from a uid that does not own the tree. setpriv's own failures
# are separated from git's first: without CAP_SETGID `--clear-groups` fails, and
# blaming safe.directory for that would send the next reader to the wrong place.
    { if ! command -v setpriv >/dev/null 2>&1; then \
        echo "setpriv unavailable - safe.directory asserted by configuration only"; \
      elif ! setpriv --reuid=65534 --regid=65534 --clear-groups true 2>/dev/null; then \
        echo "setpriv cannot drop privileges here - asserted by configuration only"; \
      else \
        setpriv --reuid=65534 --regid=65534 --clear-groups \
          git -C /opt/esp-matter rev-parse HEAD >/dev/null \
          || { echo "git still refuses /opt/esp-matter from an unprivileged uid" >&2; \
               exit 1; }; \
# The documented invocation goes through the entrypoint, which runs `set -e` and
# sources both export.sh scripts before the command - so the command working is
# not the same as the recipe in the README working. This runs that path, as the
# same unprivileged uid.
        setpriv --reuid=65534 --regid=65534 --clear-groups \
          /opt/esp/esp_matter_entrypoint.sh git -C /opt/esp-matter rev-parse HEAD >/dev/null \
          || { echo "the documented entrypoint path fails for an unprivileged uid" >&2; \
               exit 1; }; \
        echo "safe.directory verified from an unprivileged uid, entrypoint included"; \
      fi; } && \
    echo "ESP-Matter ${ESP_MATTER_VERSION} installation verified successfully"

# Use custom entrypoint to activate environments (like entrypoint.sh in esp-idf image)
ENTRYPOINT ["/opt/esp/esp_matter_entrypoint.sh"]

CMD ["/bin/bash"]

