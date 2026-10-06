#!/bin/sh
# The smoke check, in one place: the Dockerfile's verification layer runs it at
# build time, and the README runs the same file against a published image, so the
# two cannot drift apart. POSIX sh, because that layer runs under dash.
#
#   sh /opt/smoke-src/verify.sh <build-dir>
#
# Configures, builds and ctests the project beside it, then runs clang-tidy over
# its source through the compile database that build wrote, runs the pytest file
# beside it under pytest-xdist, and last checks that none of the libraries the
# image dropped - GoogleTest, GMock, paho - has come back. The build directory is
# left for the caller to remove.
set -eu

build="${1:?usage: verify.sh <build-dir>}"
src="$(cd "$(dirname "$0")" && pwd)"

cmake -S "${src}" -B "${build}" -G Ninja
# A cache nothing is wired to is indistinguishable from a working one until someone
# measures a rebuild, so what is checked is that CMake took the launcher.
grep -qx "CMAKE_CXX_COMPILER_LAUNCHER:STRING=ccache" "${build}/CMakeCache.txt" \
  || { echo "cmake did not take the ccache launcher" >&2; exit 1; }
# Written because the image sets CMAKE_EXPORT_COMPILE_COMMANDS, and asserted
# because clang-tidy given a `-p` with no database in it falls back to compiling
# with no flags at all - which, on this file, still passes.
[ -s "${build}/compile_commands.json" ] \
  || { echo "cmake wrote no compile database - clang-tidy -p has nothing to read" >&2; \
       exit 1; }
cmake --build "${build}"
ctest --test-dir "${build}" --output-on-failure
# Run, not asked for its version: a wheel whose binary cannot find its own
# resource directory answers `--version` perfectly and then fails on the first real
# file. And real analysis over that file: `--checks=-*` alone exits 0 whatever
# happens, so the check set is what makes a compilation error - a missing resource
# directory, an unusable system header - fail this.
clang-tidy --quiet "--checks=-*,bugprone-*" -p "${build}" "${src}/smoke.cpp"

# pytest-xdist is pinned so a consumer can run its suite with `-n auto`, so that is
# what runs: the plugin loaded through its entry point, as a consumer's pytest
# loads it, under the pinned pytest, with the test asserting it ran in a worker.
# Writing nothing beside the sources - no .pytest_cache, no __pycache__ - is what
# lets this run as any uid against a published image. The base temporary
# directory goes into the build directory for the same reason, and because xdist
# creates it even for a suite that asks for none: left at its default it would be
# /tmp/pytest-of-root, which the build layer refuses to leave behind.
PYTHONDONTWRITEBYTECODE=1 pytest -p no:cacheprovider -n auto -q \
  --basetemp "${build}/pytest" "${src}/test_xdist.py"

# GoogleTest, GMock and paho.mqtt.c were dropped from this image (the comment at
# its apt layer says why), and an absence is kept by nothing unless something
# looks: a package a later bump pulls in would bring GTestConfig.cmake back and the
# build would stay green. So the names those three install under are searched for
# where a build's find_* would look - those three, not every library there could
# be: the toolchain itself is a set of -dev packages, so a rule over all of them
# would be a list of exceptions. One walk, since a clean image matches nothing and
# every pattern would otherwise walk the whole tree.
found="$(find /usr /opt -xdev \( -name 'libgtest*' -o -name 'libgmock*' \
           -o -name 'GTestConfig.cmake' -o -name 'GMockConfig.cmake' \
           -o -name 'gtest.h' -o -name 'gmock.h' \
           -o -name 'libpaho-mqtt3*' -o -name 'MQTTAsync.h' \) -print -quit 2>/dev/null || true)"
[ -z "${found}" ] \
  || { echo "${found} is in this image - GoogleTest, GMock and paho were dropped from it" >&2; \
       exit 1; }
