#!/bin/sh
# The smoke check, in one place: the Dockerfile's verification layer runs it at
# build time, and the README runs the same file against a published image, so the
# two cannot drift apart. POSIX sh, because that layer runs under dash.
#
#   sh /opt/smoke-src/verify.sh <build-dir>
#
# Configures, builds and ctests the project beside it, then runs clang-tidy over
# its source through the compile database that build wrote, and last checks that
# no test framework or third-party library the image dropped has come back. The
# build directory is left for the caller to remove.
set -eu

build="${1:?usage: verify.sh <build-dir>}"
src="$(cd "$(dirname "$0")" && pwd)"

cmake -S "${src}" -B "${build}" -G Ninja
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
# Real analysis over a real file: `--checks=-*` alone exits 0 whatever happens,
# so the check set is what makes a compilation error - a missing resource
# directory, an unusable system header - fail this.
clang-tidy --quiet "--checks=-*,bugprone-*" -p "${build}" "${src}/smoke.cpp"

# The image promises a toolchain and no libraries to link beyond the standard
# one (the comment at its apt layer says why), and a promise of absence is kept
# by nothing unless something looks: a package a later bump pulls in would bring
# GTestConfig.cmake back and the build would stay green. So the names those
# libraries install under are searched for where a build's find_* would look.
# Quoted in the list, so the shell does not expand them against the cwd.
for name in 'libgtest*' 'libgmock*' 'GTestConfig.cmake' 'GMockConfig.cmake' \
            'gtest.h' 'libpaho-mqtt3*' 'MQTTAsync.h'; do
  found="$(find /usr /opt -xdev -name "${name}" -print -quit 2>/dev/null || true)"
  [ -z "${found}" ] \
    || { echo "${found} is in this image - it carries no test framework or third-party library" >&2; \
         exit 1; }
done
