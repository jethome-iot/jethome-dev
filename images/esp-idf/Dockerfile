# ESP-IDF Development Image
# Based on official Espressif image
# Original: https://github.com/espressif/esp-idf/blob/master/tools/docker/Dockerfile

ARG IDF_BASE_TAG=v5.4.1

FROM espressif/idf:${IDF_BASE_TAG}

# Use bash for all RUN commands (needed for QEMU emulation compatibility)
SHELL ["/bin/bash", "-c"]

# Install only additional tools not in base image
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    # JSON processor for CI/CD scripting
    jq \
    # Code coverage tool
    gcovr \
    # Clean up
    && apt-get autoremove -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Create optional ccache directory for multi-user environment
# ccache is already installed and IDF_CCACHE_ENABLE=1 is set in base image
# Users can configure ccache via environment variables or mount their own cache
RUN mkdir -p /opt/ccache && \
    chmod 1777 /opt/ccache

# Install Python testing packages into ESP-IDF virtual environment
# Source export.sh to activate the correct Python environment
RUN export IDF_PATH_FORCE=1 && \
    source ${IDF_PATH}/export.sh && \
    pip install --no-cache-dir \
    # Testing frameworks
    pytest \
    pytest-embedded \
    pytest-embedded-serial-esp \
    pytest-embedded-idf \
    pytest-embedded-qemu \
    pytest-timeout \
    pytest-cov

# Set working directory
WORKDIR /workspace

# Verify installation
RUN export IDF_PATH_FORCE=1 && \
    source ${IDF_PATH}/export.sh && \
    python --version && \
    pytest --version && \
    jq --version && \
    idf.py --version && \
    echo "ESP-IDF installation verified successfully"

CMD ["/bin/bash"]

