# Build-time smoke project for the image's verification layer, built and checked
# by verify.sh beside it.
#
# It is not a test suite for anything a user writes - it exists so the last layer
# of the Dockerfile can prove, rather than assume, that an ordinary CMake project
# configures, builds with Ninja through the ccache launcher, links the standard
# library and threads, and runs under ctest - and that the build leaves behind the
# compile database clang-tidy is then run against. It links nothing else because
# the image carries nothing else to link (the Dockerfile's apt layer says why).
#
# It is compiled inside the image and its build tree is deleted afterwards. The
# sources are not: they stay at /opt/smoke-src, so the same check can be re-run
# against a published image without this repository at hand.
#
# use-after-scope.cpp beside it is deliberately not built here: it must fail under
# clang's ASan, and the Dockerfile compiles and runs it on its own.
cmake_minimum_required(VERSION 3.22)
project(jethome_host_smoke CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Threads REQUIRED)

enable_testing()

add_executable(smoke smoke.cpp)
target_link_libraries(smoke PRIVATE Threads::Threads)

add_test(NAME smoke COMMAND smoke)
