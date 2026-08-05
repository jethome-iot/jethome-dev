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
    # Test harness, fully pinned; an unpinned list re-resolves to newest-on-PyPI
    # on every rebuild (issue #18). Bump the whole row as one unit.
    #
    # pytest-embedded-serial is transitive (via -serial-esp) and named here so it
    # cannot float on its own. esptool is pinned even though ESP-IDF installs it:
    # pytest-embedded-serial-esp 2.8.1 requires esptool<6,>=5.2 and pip overwrites
    # the SDK's copy, so this image runs esptool 5.3.1 against ESP-IDF 5.5's
    # constraint esptool~=4.12. That divergence is deliberate and verified. Do NOT
    # "fix" it by editing espidf.constraints.*.txt (a cache with a 1-day TTL), by
    # re-pointing PIP_CONSTRAINT (mutable upstream), or by arming
    # IDF_PYTHON_CHECK_CONSTRAINTS (every idf.py call would exit non-zero).
    # It collapses on its own at ESP-IDF 6.0, whose constraints already pair
    # esptool 5.x with pytest-embedded 2.x. Never relax the <6 bound while on 5.5.
    pytest==9.1.1 \
    pytest-embedded==2.8.1 \
    pytest-embedded-serial==2.8.1 \
    pytest-embedded-serial-esp==2.8.1 \
    pytest-embedded-idf==2.8.1 \
    pytest-embedded-qemu==2.8.1 \
    pytest-timeout==2.4.0 \
    pytest-cov==7.1.0 \
    esptool==5.3.1 \
 && python -m pip check

# Set working directory
WORKDIR /workspace

# Verify installation
#
# esptool is printed because it is exactly what changed underneath without anyone
# noticing: nothing here installs it directly, it arrives through
# pytest-embedded-serial-esp and overwrites the copy ESP-IDF shipped. `idf.py
# flash` runs it - components/esptool_py/esptool/esptool.py is a shim around
# `python -m esptool` - so a layer that prints python, pytest and idf.py but not
# esptool cannot tell a good build from the one issue #18 describes.
#
# The freeze is written to a file rather than piped, so the image carries its own
# version snapshot and no pipe can swallow a failure.
#
# The esptool line is an assertion, not a listing: `grep -E '^esptool'` would pass
# on any version, and "any version" is exactly the bug - ESP-IDF's own environment
# ships 4.12.0 and anything reinstalling it would go unnoticed. It repeats the
# number from the pip layer on purpose; the two disagreeing fails the build here,
# loudly, instead of publishing an image whose flasher contradicts its Dockerfile.
RUN export IDF_PATH_FORCE=1 && \
    source ${IDF_PATH}/export.sh && \
    python --version && \
    pytest --version && \
    esptool version && \
    pip freeze > /opt/esp/python-packages.txt && \
    grep -qx 'esptool==5.3.1' /opt/esp/python-packages.txt && \
    grep -E '^(pytest|esptool)' /opt/esp/python-packages.txt && \
    jq --version && \
    idf.py --version && \
    echo "ESP-IDF installation verified successfully"

CMD ["/bin/bash"]

