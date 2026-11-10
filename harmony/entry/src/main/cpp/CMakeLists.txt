cmake_minimum_required(VERSION 3.5.0)
project(uu_core_napi)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})
set(UU_RUST_LIB ${NATIVERENDER_ROOT_PATH}/libs/${OHOS_ARCH}/libuu_core.a)
# Rust dependencies are staged explicitly by scripts/harmony/build-native.*.
# CMake never installs toolchains or writes caches into the user's home directory.
if(NOT EXISTS "${UU_RUST_LIB}")
    message(FATAL_ERROR "Missing ${UU_RUST_LIB}. Run scripts/harmony/build-native.ps1 or build-native.sh for ${OHOS_ARCH} first.")
endif()

include_directories(${NATIVERENDER_ROOT_PATH}/include)

# Vendored libopus 1.4 (BSD-3-Clause, see third_party/opus/COPYING). Only the
# decoder is used; intrinsics are disabled so the OHOS cross build has no
# runtime CPU-detection dependency and produces identical C behaviour on all
# device ABIs. Opus decodes RTP payloads to 48 kHz stereo S16 for OHAudio.
set(OPUS_BUILD_SHARED_LIBRARY OFF CACHE BOOL "" FORCE)
set(OPUS_BUILD_TESTING OFF CACHE BOOL "" FORCE)
set(OPUS_BUILD_PROGRAMS OFF CACHE BOOL "" FORCE)
set(OPUS_DISABLE_INTRINSICS ON CACHE BOOL "" FORCE)
set(OPUS_INSTALL_PKG_CONFIG_MODULE OFF CACHE BOOL "" FORCE)
set(OPUS_INSTALL_CMAKE_CONFIG_MODULE OFF CACHE BOOL "" FORCE)
set(UU_PARENT_BUILD_SHARED_LIBS ${BUILD_SHARED_LIBS})
set(BUILD_SHARED_LIBS OFF)
add_subdirectory(third_party/opus EXCLUDE_FROM_ALL)
set(BUILD_SHARED_LIBS ${UU_PARENT_BUILD_SHARED_LIBS})

add_library(uu_core SHARED
    napi_init.cpp
    src/media_pipeline.cpp
    src/input_bridge.cpp
    src/gamepad_bridge.cpp
)


target_compile_options(uu_core PRIVATE -std=c++17 -Wall -Wextra)
target_compile_definitions(uu_core PRIVATE OHOS_ARCH=${OHOS_ARCH})

target_link_libraries(uu_core PUBLIC
    libace_napi.z.so
    libhilog_ndk.z.so
    libnative_window.so
    libnative_buffer.so
    libnative_media_codecbase.so
    libnative_media_core.so
    libnative_media_vdec.so
    libohaudio.so
    libohgame_controller.z.so
    opus
    dl
    pthread
    m
    ${UU_RUST_LIB}
)

# libuu_core.a is produced by:
#   cargo build --release --target aarch64-unknown-linux-ohos --features harmony
# and copied to libs/arm64-v8a/libuu_core.a by scripts/harmony/build-native.sh.
