# ESP-IDF Development Image
# Based on official Espressif image
# Original: https://github.com/espressif/esp-idf/blob/master/tools/docker/Dockerfile

ARG IDF_BASE_TAG=v5.5.5

FROM espressif/idf:${IDF_BASE_TAG}

# Use bash for all RUN commands: the layers below call the bash builtin `source`,
# which /bin/sh does not have. (This once said "needed for QEMU emulation
# compatibility" - CI no longer emulates anything, but the reason above always was
# the real one.)
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

