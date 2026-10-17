# ESP-IDF Development Image
# Based on official Espressif image
# Original: https://github.com/espressif/esp-idf/blob/master/tools/docker/Dockerfile

ARG IDF_BASE_TAG=v5.5.6

FROM espressif/idf:${IDF_BASE_TAG}

# Re-declared after FROM: an ARG stated before it is out of scope below, so the
# LABEL would otherwise expand to the empty string - silently, since Docker does
# not object to an undefined variable.
ARG IDF_BASE_TAG

# The ESP-IDF version this image carries, readable from the registry without
# pulling several gigabytes to find out. The tag says it too, but a consumer that
# pins by digest - the only pin that cannot be moved under it - deliberately does
# not keep the tag, so the tag is exactly what it cannot read. The verification
# layer at the bottom holds this to what the SDK itself reports, so it is a fact
# about the image rather than a claim it makes.
LABEL dev.jethome.idf.version="${IDF_BASE_TAG}" \
      org.opencontainers.image.version="idf-${IDF_BASE_TAG}" \
      org.opencontainers.image.base.name="espressif/idf:${IDF_BASE_TAG}" \
      org.opencontainers.image.source="https://github.com/jethome-iot/jethome-dev" \
      org.opencontainers.image.description="ESP-IDF for every ESP32 chip, plus pytest and QEMU emulation for some of them"

# `image.version` is set here because a LABEL is inherited through FROM and this
# one was arriving from three images away: ubuntu sets it to `24.04`, espressif/idf
# does not override it, and so every published esp-idf image announced itself as
# version 24.04.
#
# The value is assembled from the same ARG the variant's tag is checked against,
# so a version bump cannot move one without the other: `check-versions.sh` holds
# `args` and the ARG defaults to each other, and requires the tag to *name* every
# version it is built with. Note what that is not - it is a token-boundary match,
# not equality, so a variant tagged `idf-v<version>-slim` would pass the checker
# while this label read `idf-v<version>`. The label states the version the image
# was built with; the index annotation states the tag. No such variant exists
# today, and both answers are true ones to different questions.
#
# The index annotations the manifest job writes carry the same field, and cannot
# be inherited at all; these labels are what an image already pulled reports, and
# what a local `./scripts/build.sh` produces, where no manifest job ran.

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
    # pytest-embedded-serial-esp 2.9.3 requires esptool<6,>=5.2 and pip overwrites
    # the SDK's copy, so this image runs esptool 5.3.1 against ESP-IDF 5.5's
    # constraint esptool~=4.12. That divergence is deliberate and verified. Do NOT
    # "fix" it by editing espidf.constraints.*.txt (a cache with a 1-day TTL), by
    # re-pointing PIP_CONSTRAINT (mutable upstream), or by arming
    # IDF_PYTHON_CHECK_CONSTRAINTS (every idf.py call would exit non-zero).
    # It collapses on its own at ESP-IDF 6.0, whose constraints already pair
    # esptool 5.x with pytest-embedded 2.x. Never relax the <6 bound while on 5.5.
    pytest==9.1.1 \
    pytest-embedded==2.9.3 \
    pytest-embedded-serial==2.9.3 \
    pytest-embedded-serial-esp==2.9.3 \
    pytest-embedded-idf==2.9.3 \
    pytest-embedded-qemu==2.9.3 \
    pytest-timeout==2.4.0 \
    pytest-cov==7.1.0 \
    esptool==5.3.1 \
 && python -m pip check

# A directory the component manager writes on every configure, open to every uid.
#
# ESP-IDF 5.5.6 ships tools/idf_extra_components.yml (every line of it commented
# out). Its presence alone is enough: `prepare_dep_dirs` then resolves it on each
# CMake configure and writes the result to
# $IDF_TOOLS_PATH/root_managed_components/idf<major.minor>/dependencies.lock,
# creating the directories first. The base image has them nowhere and /opt/esp
# belongs to root, so under the documented `-u $(id -u):$(id -g)` every project
# stops at configure with a PermissionError - while every check run as root, this
# image's own included, stays green. 5.5.5 had no such file.
#
# The directory is derived from IDF_TOOLS_PATH alone (idf_component_tools
# config_dir(), falling back to ~/.espressif); the component manager reads no
# variable of its own for it, and IDF_TOOLS_PATH is also where the toolchains are
# found, so it cannot be pointed elsewhere. Hence the directory, created here.
#
# Only the top level, and empty. The lock records the target and is rewritten in
# place (`open(path, 'w')`) whenever that changes, so a lock root wrote at build
# time would refuse the caller at their first `set-target` - the version
# subdirectory is left to the first uid that configures, which then owns it.
# Mode 1777 as on /tmp. What this covers is one uid per container, which is what
# `docker run -u` gives: a second uid in the same container finds the first
# one's subdirectory and fails the moment it changes the target. The verification
# layer below configures a project as an arbitrary uid and returns this directory
# empty.
RUN install -d -m 1777 "${IDF_TOOLS_PATH}/root_managed_components"

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
# The idf.py line is an assertion too, and for a reason of its own: the
# dev.jethome.idf.version label near the top of this file is what a consumer reads
# instead of pulling several gigabytes, and a label is only worth reading if the
# image cannot publish one that contradicts itself. Compared for equality against
# what the SDK reports (`ESP-IDF v<version>`), so a tag naming one version while the
# base carries another fails here rather than downstream.
#
# The esptool line is an assertion, not a listing: `grep -E '^esptool'` would pass
# on any version, and "any version" is exactly the bug - ESP-IDF's own environment
# ships 4.12.0 and anything reinstalling it would go unnoticed. It repeats the
# number from the pip layer on purpose; the two disagreeing fails the build here,
# loudly, instead of publishing an image whose flasher contradicts its Dockerfile.
#
# The last step configures a project the way the documented invocation does, as a
# uid that is not root - an arbitrary one with no passwd entry, as `docker run -u
# $(id -u):$(id -g)` gives - because every other line here runs as root, and root
# is the one caller the root_managed_components layer above changes nothing for.
# `setpriv` keeps the environment export.sh just set up; HOME points at the scratch
# directory, so nothing the run caches outlives it. What the run leaves in
# root_managed_components belongs to that uid and is deleted before the layer is
# committed: shipped, it would refuse every other uid. The mode is then asserted,
# since the directory is only useful if it reaches the image as created. A builder
# where setpriv cannot drop privileges skips the configure and says so, as the
# esp-matter layer does for its own unprivileged probe; the mode is checked either
# way.
RUN export IDF_PATH_FORCE=1 && \
    source ${IDF_PATH}/export.sh && \
    python --version && \
    pytest --version && \
    esptool version && \
    pip freeze > /opt/esp/python-packages.txt && \
    grep -qx 'esptool==5.3.1' /opt/esp/python-packages.txt && \
    grep -E '^(pytest|esptool)' /opt/esp/python-packages.txt && \
    jq --version && \
    idf_reported="$(idf.py --version)" && \
    echo "${idf_reported}" && \
    { if [[ "${IDF_BASE_TAG}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then \
        [ "${idf_reported}" = "ESP-IDF ${IDF_BASE_TAG}" ] \
          || { echo "expected 'ESP-IDF ${IDF_BASE_TAG}', got '${idf_reported}'" >&2; \
               exit 1; }; \
      else \
        echo "IDF_BASE_TAG '${IDF_BASE_TAG}' is not an exact version - label not asserted"; \
      fi; } && \
    rmc="${IDF_TOOLS_PATH}/root_managed_components" && \
    { if ! setpriv --reuid=54321 --regid=54321 --clear-groups true 2>/dev/null; then \
        echo "setpriv cannot drop privileges here - configure as another uid not run"; \
      else \
        smoke="$(mktemp -d)" && \
        cp -r "${IDF_PATH}/examples/get-started/hello_world" "${smoke}/project" && \
        chown -R 54321:54321 "${smoke}" && \
        { setpriv --reuid=54321 --regid=54321 --clear-groups env HOME="${smoke}" \
            idf.py -C "${smoke}/project" reconfigure > "${smoke}/configure.log" 2>&1 \
          || { tail -n 30 "${smoke}/configure.log" >&2; \
               echo "configure as uid 54321 failed" >&2; exit 1; }; } && \
        echo "configure as uid 54321: ok" && \
        rm -rf "${smoke}"; \
      fi; } && \
    find "${rmc}" -mindepth 1 -delete && \
    { [ "$(stat -c %a "${rmc}")" = 1777 ] \
        || { echo "${rmc} is not mode 1777" >&2; exit 1; }; } && \
    echo "ESP-IDF installation verified successfully"

CMD ["/bin/bash"]

