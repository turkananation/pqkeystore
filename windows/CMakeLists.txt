# The Flutter tooling requires a Visual Studio that includes CMake 3.14 or
# later. Do not increase this version without a documented reason.
cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "pqkeystore")
project(${PROJECT_NAME} LANGUAGES CXX)

cmake_policy(VERSION 3.14...3.25)

# Must be "<package name>_plugin"; the Flutter tool links this target name.
set(PLUGIN_NAME "pqkeystore_plugin")

list(APPEND PLUGIN_SOURCES
  "pq_keystore_contract.cpp"
  "pq_keystore_contract.h"
  "pq_keystore_dpapi_store.cpp"
  "pq_keystore_dpapi_store.h"
  "pq_keystore_plugin.cpp"
  "pq_keystore_plugin.h"
)

add_library(${PLUGIN_NAME} SHARED
  "include/pqkeystore/pq_keystore_plugin_c_api.h"
  "pq_keystore_plugin_c_api.cpp"
  ${PLUGIN_SOURCES}
)

apply_standard_settings(${PLUGIN_NAME})

set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
# crypt32: DPAPI. bcrypt: SHA-256 file names. advapi32: SID/SDDL.
# shell32/ole32: known-folder lookup.
target_link_libraries(${PLUGIN_NAME} PRIVATE
  flutter flutter_wrapper_plugin crypt32 bcrypt advapi32 shell32 ole32)

set(pqkeystore_bundled_libraries
  ""
  PARENT_SCOPE
)

# === Tests ===
# Enabled only when building the example (which sets this variable).
if (${include_${PROJECT_NAME}_tests})
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
  test/pq_keystore_plugin_test.cpp
  ${PLUGIN_SOURCES}
)
apply_standard_settings(${TEST_RUNNER})
target_include_directories(${TEST_RUNNER} PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}")
target_link_libraries(${TEST_RUNNER} PRIVATE
  flutter_wrapper_plugin crypt32 bcrypt advapi32 shell32 ole32)
target_link_libraries(${TEST_RUNNER} PRIVATE gtest_main gmock)
# flutter_wrapper_plugin has link dependencies on the Flutter DLL.
add_custom_command(TARGET ${TEST_RUNNER} POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
  "${FLUTTER_LIBRARY}" $<TARGET_FILE_DIR:${TEST_RUNNER}>
)

include(GoogleTest)
gtest_discover_tests(${TEST_RUNNER})
endif()
