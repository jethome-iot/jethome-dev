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

FROM ${BASE_IMAGE}

# Re-declare build arguments after FROM
ARG ESP_MATTER_VERSION
ARG ESP_MATTER_REF

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

# Answers "what is actually in here" without starting the container.
LABEL org.opencontainers.image.revision="${ESP_MATTER_REF}" \
      org.opencontainers.image.version="${ESP_MATTER_VERSION}"

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
    idf.py --version && \
    echo "ESP-Matter ${ESP_MATTER_VERSION} installation verified successfully"

# Use custom entrypoint to activate environments (like entrypoint.sh in esp-idf image)
ENTRYPOINT ["/opt/esp/esp_matter_entrypoint.sh"]

CMD ["/bin/bash"]

