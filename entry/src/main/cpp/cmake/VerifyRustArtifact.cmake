if(NOT DEFINED ENGINE_RUST_ROOT OR NOT DEFINED RUST_STATIC_LIB)
    message(FATAL_ERROR "ENGINE_RUST_ROOT and RUST_STATIC_LIB are required")
endif()

if(NOT EXISTS "${RUST_STATIC_LIB}")
    message(FATAL_ERROR
        "Rust artifact for ${OHOS_ARCH} is missing: ${RUST_STATIC_LIB}. "
        "Run scripts/build-native.ps1 -Abi ${OHOS_ARCH} before building the HAP."
    )
endif()

file(GLOB_RECURSE RUST_CRATE_INPUTS
    "${ENGINE_RUST_ROOT}/crates/*/src/*.rs"
    "${ENGINE_RUST_ROOT}/crates/*/Cargo.toml"
)
list(APPEND RUST_CRATE_INPUTS
    "${ENGINE_RUST_ROOT}/Cargo.toml"
    "${ENGINE_RUST_ROOT}/Cargo.lock"
    "${ENGINE_RUST_ROOT}/rust-toolchain.toml"
)

foreach(RUST_INPUT IN LISTS RUST_CRATE_INPUTS)
    if(EXISTS "${RUST_INPUT}" AND "${RUST_INPUT}" IS_NEWER_THAN "${RUST_STATIC_LIB}")
        message(FATAL_ERROR
            "Rust artifact for ${OHOS_ARCH} is stale. "
            "${RUST_INPUT} is newer than ${RUST_STATIC_LIB}. "
            "Run scripts/build-native.ps1 -Abi ${OHOS_ARCH} before building the HAP."
        )
    endif()
endforeach()

message(STATUS "Rust artifact for ${OHOS_ARCH} is current: ${RUST_STATIC_LIB}")
