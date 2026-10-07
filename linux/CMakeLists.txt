# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. Do not increase this version without a documented reason.
cmake_minimum_required(VERSION 3.10)

set(PROJECT_NAME "pqkeystore")
project(${PROJECT_NAME} LANGUAGES CXX)

# Must be "<package name>_plugin"; the Flutter tool links this target name.
set(PLUGIN_NAME "pqkeystore_plugin")

# Secret Service client. There is intentionally no file fallback.
# Build dependency: libsecret-1-dev (Debian/Ubuntu), libsecret-devel (Fedora).
find_package(PkgConfig REQUIRED)
pkg_check_modules(LIBSECRET REQUIRED IMPORTED_TARGET libsecret-1>=0.18)

list(APPEND PLUGIN_SOURCES
  "pq_keystore_contract.cc"
  "pq_keystore_secret_store.cc"
)

add_library(${PLUGIN_NAME} SHARED
  "pq_keystore_plugin.cc"
  ${PLUGIN_SOURCES}
)

apply_standard_settings(${PLUGIN_NAME})

set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter)
target_link_libraries(${PLUGIN_NAME} PRIVATE PkgConfig::GTK)
target_link_libraries(${PLUGIN_NAME} PRIVATE PkgConfig::LIBSECRET)

# libsecret is a system library; nothing is bundled.
set(pqkeystore_bundled_libraries
  ""
  PARENT_SCOPE
)

# === Tests ===
# Enabled only when building the example (which sets this variable).
if (${include_${PROJECT_NAME}_tests})
if(${CMAKE_VERSION} VERSION_LESS "3.11.0")
message("Unit tests require CMake 3.11.0 or later")
else()
set(TEST_RUNNER "${PROJECT_NAME}_test")
enable_testing()

include(FetchContent)
if(POLICY CMP0135)
  cmake_policy(SET CMP0135 NEW)
endif()
FetchContent_Declare(
  googletest
  URL https://github.com/google/googletest/archive/refs/tags/v1.15.2.zip
)
set(gtest_force_shared_crt ON CACHE BOOL "" FORCE)
set(INSTALL_GTEST OFF CACHE BOOL "Disable installation of googletest" FORCE)
FetchContent_MakeAvailable(googletest)

add_executable(${TEST_RUNNER}
  test/pq_keystore_contract_test.cc
  ${PLUGIN_SOURCES}
)
apply_standard_settings(${TEST_RUNNER})
target_include_directories(${TEST_RUNNER} PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}")
target_link_libraries(${TEST_RUNNER} PRIVATE flutter)
target_link_libraries(${TEST_RUNNER} PRIVATE PkgConfig::GTK)
target_link_libraries(${TEST_RUNNER} PRIVATE PkgConfig::LIBSECRET)
target_link_libraries(${TEST_RUNNER} PRIVATE gtest_main gmock)

include(GoogleTest)
gtest_discover_tests(${TEST_RUNNER})
endif()
endif()
