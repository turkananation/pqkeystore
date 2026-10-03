cmake_minimum_required(VERSION 3.10)
project(pqkeystore_plugin)

set(PLUGIN_NAME pq_keystore_plugin)

add_library(${PLUGIN_NAME} SHARED
  "pq_keystore_plugin.cc"
)

target_compile_definitions(${PLUGIN_NAME} PRIVATE PQ_KEYSTORE_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}"
)
