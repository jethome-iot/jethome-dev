# ESP-Matter Development Image
# Build arguments for version pinning
ARG BASE_IMAGE_TAG=idf-v5.4.1
ARG ESP_MATTER_VERSION=v1.4.2

# Use our esp-idf image as base
# For local builds: Uses default idf-v5.4.1 tag
# For CI/CD: Override with --build-arg BASE_IMAGE_TAG=idf-v5.4.1-linux-${ARCH}
FROM ghcr.io/jethome-iot/jethome-dev-esp-idf:${BASE_IMAGE_TAG}

# Re-declare build arguments after FROM
ARG ESP_MATTER_VERSION

# Install Matter prerequisites
# Based on https://docs.espressif.com/projects/esp-matter/en/latest/esp32/developing.html
RUN apt-get update && apt-get install -y \
    # Build essentials
    pkg-config \
    ninja-build \
    # Python development
    python3-venv \
    python3-pip \
    # Matter SDK dependencies
    libssl-dev \
    libdbus-1-dev \
    libglib2.0-dev \
    libavahi-client-dev \
    # Clean up
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Clone esp-matter repository
# Using shallow clone to reduce image size
# ESP-Matter uses release branches (e.g., release/v1.4.2)
WORKDIR /opt
RUN git clone --depth 1 --branch release/${ESP_MATTER_VERSION} \
    https://github.com/espressif/esp-matter.git && \
    cd esp-matter && \
    git submodule update --init --depth 1

# Checkout connectedhomeip submodules
# Include both linux and darwin platforms for maximum compatibility
WORKDIR /opt/esp-matter/connectedhomeip/connectedhomeip
RUN ./scripts/checkout_submodules.py --platform esp32 linux darwin --shallow

# Install esp-matter (without host tools)
# Host tools (chip-tool, chip-cert, etc.) are excluded to reduce image size
# Use --break-system-packages since this is a containerized environment
WORKDIR /opt/esp-matter
RUN PIP_BREAK_SYSTEM_PACKAGES=1 ./install.sh --no-host-tool

# Set ESP-Matter environment variables
ENV ESP_MATTER_PATH=/opt/esp-matter

# Create entrypoint script that activates both ESP-IDF and ESP-Matter environments
RUN printf '#!/bin/bash\n\
set -e\n\
\n\
# Source ESP-IDF environment (from base image)\n\
if [ -f "${IDF_PATH}/export.sh" ]; then\n\
    . "${IDF_PATH}/export.sh" > /dev/null 2>&1\n\
fi\n\
\n\
# Source ESP-Matter environment\n\
if [ -f "${ESP_MATTER_PATH}/export.sh" ]; then\n\
    . "${ESP_MATTER_PATH}/export.sh" > /dev/null 2>&1\n\
fi\n\
\n\
# Execute the command\n\
exec "$@"\n\
' > /opt/esp-matter/entrypoint.sh && \
    chmod +x /opt/esp-matter/entrypoint.sh

# Set working directory back to workspace
WORKDIR /workspace

# Verify installation
RUN bash -c '. ${IDF_PATH}/export.sh && \
    . ${ESP_MATTER_PATH}/export.sh && \
    python --version && \
    idf.py --version && \
    echo "ESP-Matter ${ESP_MATTER_VERSION} installation verified successfully"'

# Use custom entrypoint to activate environments
ENTRYPOINT ["/opt/esp-matter/entrypoint.sh"]

CMD ["/bin/bash"]

