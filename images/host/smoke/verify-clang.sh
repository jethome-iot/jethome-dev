#!/bin/sh
# The clang check, in one place, for the reason verify.sh is one: the Dockerfile's
# verification layer runs it at build time, and the README runs the same file
# against a published image. POSIX sh, because that layer runs under dash.
#
#   sh /opt/smoke-src/verify-clang.sh <clang-major>
#
# The major is an argument rather than something this script looks up: the layer
# has it as CLANG_VERSION, a published image carries it as the
# dev.jethome.clang.version label, and either is the number the image promises -
# finding "some clang++-*" here would pass on the wrong one. Scratch files go to a
# directory of its own and leave with it, since the layer requires /tmp to end empty.
#
# clang is asserted by what it catches, not by the fact that it answers: the
# property this image promises is that clang's ASan sees the use-after-scope GCC's
# misses. One run of use-after-scope.cpp covers a missing compiler, a missing
# runtime and a runtime whose version does not match the compiler - each fails to
# build or to report. The report must also name the probe's source file, which only
# a working llvm-symbolizer puts there.
#
# Two things checked before it keep a clang leg comparable with the GCC one. clang
# takes its libstdc++ headers from the newest GCC installation it finds, so a
# dependency pulling in a newer libstdc++-N-dev would have it compile against other
# headers than g++ does while every link still succeeded - the installation it
# selected has to be the one `gcc` is. And `cc`/`c++` stay GCC: an alternative
# registered by some future clang package would move every plain
# `cmake -S . -B build` onto clang without a word.
set -eu

clang="${1:?usage: verify-clang.sh <clang-major>}"
src="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

"clang++-${clang}" --version
"llvm-symbolizer-${clang}" --version

gcc_major="$(gcc -dumpversion)"
"clang++-${clang}" -v -E -x c++ /dev/null > "${work}/clang-gcc.txt" 2>&1
grep -q "^Selected GCC installation: .*/${gcc_major}\$" "${work}/clang-gcc.txt" \
  || { cat "${work}/clang-gcc.txt"; \
       echo "clang++-${clang} did not select GCC ${gcc_major}'s libstdc++" >&2; \
       exit 1; }
# Captured on a line of its own: inside `case` the command's status is lost, and
# a cc that cannot run at all would print nothing, match nothing and pass.
for default_compiler in cc c++; do
  reported="$("${default_compiler}" --version)" \
    || { echo "${default_compiler} does not run - it must stay GCC" >&2; exit 1; }
  case "${reported}" in
    *clang*) echo "${default_compiler} resolves to clang - it must stay GCC" >&2; exit 1 ;;
  esac
done

"clang++-${clang}" -fsanitize=address -g "${src}/use-after-scope.cpp" \
  -o "${work}/use-after-scope"
probe_status=0
"${work}/use-after-scope" > "${work}/use-after-scope.log" 2>&1 || probe_status=$?
cat "${work}/use-after-scope.log"
[ "${probe_status}" -ne 0 ] \
  || { echo "clang's ASan ran the use-after-scope probe clean" >&2; exit 1; }
grep -q 'ERROR: AddressSanitizer: stack-use-after-scope' "${work}/use-after-scope.log" \
  || { echo "clang's ASan failed the probe without reporting stack-use-after-scope" >&2; \
       exit 1; }
grep -q 'use-after-scope\.cpp:' "${work}/use-after-scope.log" \
  || { echo "the ASan report is not symbolized - llvm-symbolizer was not found" >&2; \
       exit 1; }
