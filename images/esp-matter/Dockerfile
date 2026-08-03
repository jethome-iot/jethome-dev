# ESP-Matter Development Image
# Based on https://docs.espressif.com/projects/esp-matter/en/latest/esp32/developing.html

# One argument carries the whole reference so CI can pass a digest
# (…/jethome-dev-esp-idf@sha256:…), which a tag-shaped ARG cannot express - the
# separator differs. CI pins the exact esp-idf image its own run produced; the
# default below is what a local ./scripts/build.sh uses, and it also makes the
# owner overridable instead of hardcoded, so a fork can build against its own base.
ARG BASE_IMAGE=ghcr.io/jethome-iot/jethome-dev-esp-idf:idf-v5.5.5
ARG ESP_MATTER_VERSION=v1.6

FROM ${BASE_IMAGE}

# Re-declare build arguments after FROM
ARG ESP_MATTER_VERSION

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

# Clone ESP-Matter repository and submodules
# Using shallow clones to reduce image size
WORKDIR /opt
RUN git clone --depth 1 --branch release/${ESP_MATTER_VERSION} \
    https://github.com/espressif/esp-matter.git && \
    cd esp-matter && \
    git submodule update --init --depth 1 && \
    cd connectedhomeip/connectedhomeip && \
    ./scripts/checkout_submodules.py --platform esp32 linux --shallow

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
RUN source ${IDF_PATH}/export.sh && \
    source ${ESP_MATTER_PATH}/export.sh && \
    python --version && \
    idf.py --version && \
    echo "ESP-Matter ${ESP_MATTER_VERSION} installation verified successfully"

# Use custom entrypoint to activate environments (like entrypoint.sh in esp-idf image)
ENTRYPOINT ["/opt/esp/esp_matter_entrypoint.sh"]

CMD ["/bin/bash"]

