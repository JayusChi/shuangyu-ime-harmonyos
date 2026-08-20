cmake_minimum_required(VERSION 3.5.0)
project(ShuangYuIME)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

if(DEFINED PACKAGE_FIND_FILE)
    include(${PACKAGE_FIND_FILE})
endif()

include_directories(
    ${NATIVERENDER_ROOT_PATH}
    ${NATIVERENDER_ROOT_PATH}/include
    ${NATIVERENDER_ROOT_PATH}/bridge
    ${NATIVERENDER_ROOT_PATH}/error
    ${NATIVERENDER_ROOT_PATH}/napi
)

if(NOT DEFINED OHOS_ARCH)
    set(OHOS_ARCH ${CMAKE_SYSTEM_PROCESSOR})
endif()

set(RUST_ARTIFACT_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/../../../../engine-rust/target/ohos/${OHOS_ARCH})
set(RUST_STATIC_LIB ${RUST_ARTIFACT_ROOT}/libime_ffi.a)
set(ENGINE_RUST_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/../../../../engine-rust)
set(RUST_ARTIFACT_FRESHNESS_CHECK ${CMAKE_CURRENT_SOURCE_DIR}/cmake/VerifyRustArtifact.cmake)

message(STATUS "Stage0 Native ABI: ${OHOS_ARCH}")
message(STATUS "Stage0 Rust artifact: ${RUST_STATIC_LIB}")

if(NOT EXISTS ${RUST_STATIC_LIB})
    message(FATAL_ERROR "Rust artifact not found. Run scripts/build-rust.ps1 and scripts/copy-native-artifacts.ps1 for ABI ${OHOS_ARCH}. Expected: ${RUST_STATIC_LIB}")
endif()

# Embed the exact archive identity used by the linker. Runtime logs can then
# prove which Rust artifact a device process loaded instead of inferring it
# from source timestamps or the HAP filename.
file(SHA256 ${RUST_STATIC_LIB} RUST_STATIC_LIB_SHA256)
string(SUBSTRING ${RUST_STATIC_LIB_SHA256} 0 16 RUST_BUILD_FINGERPRINT)
message(STATUS "Rust archive SHA-256: ${RUST_STATIC_LIB_SHA256}")

if(NOT EXISTS ${RUST_ARTIFACT_FRESHNESS_CHECK})
    message(FATAL_ERROR "Rust artifact freshness check not found: ${RUST_ARTIFACT_FRESHNESS_CHECK}")
endif()

# DevEco can rebuild ArkTS/C++ while silently reusing a previously copied Rust
# archive. Run this check on every native build so a HAP can never combine a
# current candidate UI with an older query engine.
add_custom_target(verify_rust_artifact ALL
    COMMAND ${CMAKE_COMMAND}
        -DENGINE_RUST_ROOT=${ENGINE_RUST_ROOT}
        -DRUST_STATIC_LIB=${RUST_STATIC_LIB}
        -DOHOS_ARCH=${OHOS_ARCH}
        -P ${RUST_ARTIFACT_FRESHNESS_CHECK}
    COMMENT "Verifying Rust archive freshness for ${OHOS_ARCH}"
    VERBATIM
)

add_library(ime_ffi STATIC IMPORTED)
set_target_properties(ime_ffi PROPERTIES
    IMPORTED_LOCATION ${RUST_STATIC_LIB}
)

add_library(ime_bridge SHARED
    napi/module_init.cpp
    napi/engine_napi.cpp
    napi/napi_converter.cpp
    bridge/engine_registry.cpp
    bridge/rust_engine_bridge.cpp
    bridge/rust_buffer.cpp
    bridge/rust_engine_handle.cpp
    error/native_error.cpp
)

add_dependencies(ime_bridge verify_rust_artifact)

target_compile_definitions(ime_bridge PRIVATE
    IME_NATIVE_ABI="${OHOS_ARCH}"
    IME_RUST_ARCHIVE_SHA256="${RUST_STATIC_LIB_SHA256}"
    IME_NATIVE_BUILD_FINGERPRINT="${RUST_BUILD_FINGERPRINT}"
)

target_link_libraries(ime_bridge PUBLIC
    ime_ffi
    libace_napi.z.so
)
