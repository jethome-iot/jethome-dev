# Use Python 3.11 slim as base for minimal footprint
FROM python:3.11-slim-bookworm

# Build arguments
ARG PIO_VERSION=6.1.18
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
RUN pip install --no-cache-dir \
    platformio==${PIO_VERSION} \
    protobuf \
    jinja2

# Install platforms: \
#   - espressif32@6.8.0 (6.12 don't work with this image)
#   - native@1.2.1 (for unit testing)
RUN pio platform install  \
    espressif32@${ESP32_PLATFORM_VERSION} \
    native@${NATIVE_PLATFORM_VERSION}

# Install Unity test framework globally
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

# Set working directory
WORKDIR /workspace

# Verify installation
RUN pio --version \
    && python --version \
    && gcc --version \
    && pio platform list

CMD ["/bin/bash"]