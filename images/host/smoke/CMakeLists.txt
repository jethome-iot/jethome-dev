# Build-time smoke project for the image's verification layer.
#
# It is not a test suite for anything a user writes - it exists so the last layer
# of the Dockerfile can prove, rather than assume, that the pieces this image
# promises actually resolve, link and run: `find_package(GTest)` finding the
# distro package, GMock linking, libpaho-mqtt3a being findable by name, and the
# paho that loads reporting the version the Dockerfile pinned.
#
# It is compiled inside the image and its build tree is deleted afterwards. The
# sources are not: they stay at /opt/smoke-src, so the same check can be re-run
# against a published image without this repository at hand.
cmake_minimum_required(VERSION 3.22)
project(jethome_host_smoke CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# The Dockerfile passes its own ARG in, so the number is stated once, in the layer
# that installs paho. Required rather than defaulted: a smoke test that silently
# checks the empty string against itself is the failure it exists to catch.
if(NOT PAHO_EXPECTED_VERSION)
  message(FATAL_ERROR "PAHO_EXPECTED_VERSION must be passed in (-DPAHO_EXPECTED_VERSION=v1.2.3)")
endif()
# The tag carries a leading `v`; the library reports the bare version.
string(REGEX REPLACE "^v" "" PAHO_EXPECTED_VERSION_BARE "${PAHO_EXPECTED_VERSION}")

find_package(GTest REQUIRED)
find_library(PAHO_MQTT3A_LIBRARY NAMES paho-mqtt3a REQUIRED)
find_path(PAHO_MQTT3A_INCLUDE_DIR NAMES MQTTAsync.h REQUIRED)

enable_testing()

add_executable(smoke smoke.cpp)
target_include_directories(smoke PRIVATE "${PAHO_MQTT3A_INCLUDE_DIR}")
target_compile_definitions(smoke PRIVATE
  PAHO_EXPECTED_VERSION="${PAHO_EXPECTED_VERSION_BARE}")
target_link_libraries(smoke PRIVATE
  GTest::gtest
  GTest::gtest_main
  GTest::gmock
  "${PAHO_MQTT3A_LIBRARY}")

add_test(NAME smoke COMMAND smoke)
