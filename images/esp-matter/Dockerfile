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
WORKDIR /opt
RUN git init esp-matter && \
    cd esp-matter && \
    git remote add origin https://github.com/espressif/esp-matter.git && \
    git fetch --depth 1 origin ${ESP_MATTER_REF} && \
    git checkout FETCH_HEAD && \
    git submodule update --init --depth 1 && \
    cd connectedhomeip/connectedhomeip && \
    ./scripts/checkout_submodules.py --platform esp32 linux --shallow

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
WORKDIR /opt/esp-matter
RUN source ${IDF_PATH}/export.sh && \
    ./install.sh --no-host-tool

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
RUN source ${IDF_PATH}/export.sh && \
    source ${ESP_MATTER_PATH}/export.sh && \
    python --version && \
    esptool version && \
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
    { git config --system --get-all safe.directory | grep -qFx '*' \
      && { echo "a blanket safe.directory '*' is set - this image claims path scoping" >&2; \
           exit 1; } || true; } && \
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

