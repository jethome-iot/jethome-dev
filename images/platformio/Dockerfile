# Use Python 3.11 slim as base for minimal footprint
FROM python:3.11-slim-bookworm

# Build arguments
ARG PIO_VERSION=6.1.18
# espressif32 6.12 does not work with this image - keep this pin
ARG ESP32_PLATFORM_VERSION=6.11.0
ARG NATIVE_PLATFORM_VERSION=1.2.1
ARG UNITY_VERSION=2.6.0

# List of PlatformIO environments to build by default
ARG PIO_ENVS="esp32 native"

# Configure PlatformIO directories
ENV PLATFORMIO_CORE_DIR=/opt/platformio
ENV PLATFORMIO_CACHE_DIR=/opt/platformio/.cache
ENV PLATFORMIO_PACKAGES_DIR=/opt/platformio/packages
ENV PLATFORMIO_PLATFORMS_DIR=/opt/platformio/platforms
ENV PLATFORMIO_GLOBALLIB_DIR=/opt/platformio/lib
ENV PLATFORMIO_BUILD_CACHE_DIR=/opt/platformio/.cache/build

# Install essential build tools only
RUN apt-get update && apt-get install -y \
    # Build essentials
    build-essential \
    pkg-config \
    cmake \
    clang-format \
    # Version control and network tools
    git \
    curl \
    wget \
    jq \
    # Clean up
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install PlatformIO and additional Python packages
#
# pin-allow: protobuf - pinning it belongs to platformio's own change, not to the
#   esp-idf one that introduced ./scripts/check-pins.sh. Neither package has a
#   consumer here (PlatformIO core requires neither, nor does the espressif32
#   platform; the READMEs offer them to the user), so "which version" is the wrong
#   question until "keep or drop" is answered.
# pin-allow: jinja2 - same change, same question. Note that jinja2's last four
#   releases were security patches, so if it stays it wants a floor and a ceiling
#   rather than an `==` that freezes the image on a future CVE.
RUN pip install --no-cache-dir \
    platformio==${PIO_VERSION} \
    protobuf \
    jinja2

# Install platforms (versions are the ARG defaults above):
#   - espressif32 for ESP32 targets
#   - native for unit testing
RUN pio platform install  \
    espressif32@${ESP32_PLATFORM_VERSION} \
    native@${NATIVE_PLATFORM_VERSION}

# Install Unity test framework globally
#
# pin-allow: Unity - `@^` is a semver range, not a pin, and it already diverged:
#   the ARG says 2.6.0 and the published image carries Unity 2.6.1. Dropping the
#   caret changes what the image contains, so it goes with the platformio change
#   together with the matching ARG bump - not into an esp-idf one.
RUN pio pkg install -g --library "throwtheswitch/Unity@^${UNITY_VERSION}" \
 && pio pkg list -g | grep Unity

# Copy pre-configured project files
COPY pio_project/ /tmp/pio_project/

# GIT init need for isp-idf.
# Use pio run to download all toolchains and frameworks
# pio run - downloads all toolchains and frameworks
# pio test - download Unity test dependencies
# - VERY LONG step, temporarily disabled
#WORKDIR /tmp/pio_project
#RUN git init \
#    && git config user.email "build@local" \
#    && git config user.name "Build System" \
#    && git add . \
#    && git commit -m "Initial commit" --no-gpg-sign --quiet \
#    && for e in $PIO_ENVS; do pio run -e "$e"; done \
#    && for e in $PIO_ENVS; do pio test -e "$e" --without-uploading --without-testing; done \
#    && rm -rf /tmp/pio_project

# ── what is in here, machine-readable ─────────────────────────────────────────
#
# This image had no labels at all: `docker image inspect` on a published
# platformio returned null, so nothing about it was readable without starting it.
# The three platform pins below are ARGs CI never passes - their Dockerfile
# default is the only source of truth, which is exactly the case where a reader
# has nowhere else to look.
#
# `image.version` is built to equal the variant's published tag, which
# check-versions.sh already holds to `args` and to this ARG default. The manifest
# job annotates the published index with the same field; annotations are not
# inherited through FROM and labels are, so an image already pulled reports these
# and a local ./scripts/build.sh produces them with no manifest job involved.
#
# No `image.base.name`: this Dockerfile names its base as a literal in FROM, and
# a label repeating it would be a second copy to keep in step. The images whose
# base tag is an ARG carry the label.
#
# Unity gets `.range`, not `.version`, because that is what UNITY_VERSION is: the
# install below asks for `@^${UNITY_VERSION}`, a semver range, and the image
# already carries 2.6.1 against an ARG saying 2.6.0. A `dev.jethome.unity.version`
# label would state a number no layer here installs. Dropping the caret changes
# what the image contains and belongs to the pin work, not to a metadata change -
# see the `pin-allow` note above the install.
LABEL org.opencontainers.image.version="pio-v${PIO_VERSION}" \
      org.opencontainers.image.source="https://github.com/jethome-iot/jethome-dev" \
      org.opencontainers.image.description="PlatformIO with ESP32 platform support + ESP-IDF + Unity testing" \
      org.opencontainers.image.licenses="MIT" \
      dev.jethome.pio.version="${PIO_VERSION}" \
      dev.jethome.espressif32.version="${ESP32_PLATFORM_VERSION}" \
      dev.jethome.native.version="${NATIVE_PLATFORM_VERSION}" \
      dev.jethome.unity.range="^${UNITY_VERSION}"

# Set working directory
WORKDIR /workspace

# Verify installation
RUN pio --version \
    && python --version \
    && gcc --version \
    && pio platform list

CMD ["/bin/bash"]