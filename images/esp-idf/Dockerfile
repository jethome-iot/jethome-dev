# ESP-IDF Development Image
# Build arguments for version pinning
ARG ESP_IDF_VERSION=v5.4.1
ARG QEMU_RELEASE_TAG=esp-develop-9.0.0-20240606
ARG QEMU_VERSION=esp_develop_9.0.0_20240606

FROM espressif/idf:${ESP_IDF_VERSION}

# Install additional system packages
RUN apt-get update && apt-get install -y \
    # JSON processor
    jq \
    # Code coverage tools
    lcov \
    gcovr \
    # Build acceleration
    ccache \
    # Additional useful tools
    vim \
    nano \
    rsync \
    # QEMU dependencies
    libglib2.0-0 \
    libpixman-1-0 \
    libslirp0 \
    # Clean up
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Configure ccache for multi-user environment
# Create ccache directory that's writable by any user
RUN mkdir -p /opt/ccache && \
    chmod 1777 /opt/ccache

# Set default ccache configuration
ENV CCACHE_DIR=/opt/ccache \
    CCACHE_MAXSIZE=2G \
    CCACHE_COMPRESS=1 \
    CCACHE_COMPRESSLEVEL=6

# Install ESP32 QEMU (detect architecture)
# Re-declare ARGs after FROM to make them available in this stage
ARG QEMU_RELEASE_TAG
ARG QEMU_VERSION
RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then \
        QEMU_ARCH="aarch64-linux-gnu"; \
    else \
        QEMU_ARCH="x86_64-linux-gnu"; \
    fi && \
    cd /tmp && \
    wget -q https://github.com/espressif/qemu/releases/download/${QEMU_RELEASE_TAG}/qemu-xtensa-softmmu-${QEMU_VERSION}-${QEMU_ARCH}.tar.xz && \
    tar -xf qemu-xtensa-softmmu-${QEMU_VERSION}-${QEMU_ARCH}.tar.xz && \
    mv qemu /opt/qemu-xtensa && \
    rm qemu-xtensa-softmmu-${QEMU_VERSION}-${QEMU_ARCH}.tar.xz && \
    wget -q https://github.com/espressif/qemu/releases/download/${QEMU_RELEASE_TAG}/qemu-riscv32-softmmu-${QEMU_VERSION}-${QEMU_ARCH}.tar.xz && \
    tar -xf qemu-riscv32-softmmu-${QEMU_VERSION}-${QEMU_ARCH}.tar.xz && \
    mv qemu /opt/qemu-riscv32 && \
    rm qemu-riscv32-softmmu-${QEMU_VERSION}-${QEMU_ARCH}.tar.xz

# Add QEMU to PATH
ENV PATH="/opt/qemu-xtensa/bin:/opt/qemu-riscv32/bin:${PATH}"

# Install Python testing and development packages
# Use ESP-IDF Python virtual environment directly to avoid QEMU emulation issues
# Let pip resolve compatible versions automatically to avoid dependency conflicts
RUN /opt/esp/python_env/idf5.4_py3.12_env/bin/pip install --no-cache-dir \
    # Testing frameworks - let pip resolve compatible versions
    pytest \
    pytest-embedded \
    pytest-embedded-serial-esp \
    pytest-embedded-idf \
    pytest-embedded-qemu \
    pytest-timeout \
    pytest-cov \
    # Code coverage
    gcovr \
    # Code quality
    pylint \
    flake8 \
    black \
    # Documentation
    sphinx \
    sphinx-rtd-theme \
    # Utilities (these are already in ESP-IDF venv but may need updates)
    pyserial \
    requests \
    pyyaml

# Set working directory
WORKDIR /workspace

# Verify installation
ARG ESP_IDF_VERSION
RUN bash -c '. ${IDF_PATH}/export.sh && \
    python --version && \
    pytest --version && \
    jq --version && \
    qemu-system-xtensa --version && \
    qemu-system-riscv32 --version && \
    gcovr --version && \
    ccache --version && \
    echo "ESP-IDF ${ESP_IDF_VERSION} installation verified successfully"'

CMD ["/bin/bash"]

