# CMake configuration for llama.cpp Android build
#
# This file configures the native build for the LLM inference engine.
# It compiles llama.cpp as a shared library that can be loaded via FFI.
#
# Strategy: Build only what we need - CPU backend with static linking,
# no dynamic backend loading (which causes std::filesystem ABI issues on Android NDK)

cmake_minimum_required(VERSION 3.18.1)

project("llama_bridge")

# Set C++ standard
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_C_STANDARD 11)

# Optimization flags for release builds
set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} -O3 -DNDEBUG -fPIC")
set(CMAKE_C_FLAGS_RELEASE "${CMAKE_C_FLAGS_RELEASE} -O3 -DNDEBUG -fPIC")

# Debug flags
# IMPORTANT: -O0 makes llama.cpp unusably slow on-device.
# Use -O2 for debug builds so inference performance is representative.
set(CMAKE_CXX_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG} -g -O2 -fPIC")
set(CMAKE_C_FLAGS_DEBUG "${CMAKE_C_FLAGS_DEBUG} -g -O2 -fPIC")

# Enable ARM NEON on arm64 for SIMD optimizations
if(${ANDROID_ABI} STREQUAL "arm64-v8a")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -march=armv8-a+fp+simd")
    set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -march=armv8-a+fp+simd")
endif()

# Path to llama.cpp source
set(LLAMA_CPP_DIR "${CMAKE_SOURCE_DIR}/../../../../../external/llama.cpp")

# Check if llama.cpp exists
if(NOT EXISTS "${LLAMA_CPP_DIR}/src/llama.cpp")
    message(FATAL_ERROR "llama.cpp not found at ${LLAMA_CPP_DIR}. "
                        "Please clone it: git clone https://github.com/ggerganov/llama.cpp external/llama.cpp")
endif()

# ============================================================================
# LLAMA.CPP SOURCES
# ============================================================================

# Core llama sources
file(GLOB LLAMA_CORE_SOURCES
    "${LLAMA_CPP_DIR}/src/*.cpp"
)

# Model-specific sources (all model architectures)
file(GLOB LLAMA_MODEL_SOURCES
    "${LLAMA_CPP_DIR}/src/models/*.cpp"
)

# ============================================================================
# GGML SOURCES - Minimal set for CPU-only Android build
# ============================================================================

# GGML core sources (excluding dynamic loader which causes std::filesystem ABI issues)
set(GGML_CORE_SOURCES
    ${LLAMA_CPP_DIR}/ggml/src/ggml.c
    ${LLAMA_CPP_DIR}/ggml/src/ggml.cpp
    ${LLAMA_CPP_DIR}/ggml/src/ggml-alloc.c
    ${LLAMA_CPP_DIR}/ggml/src/ggml-quants.c
    ${LLAMA_CPP_DIR}/ggml/src/ggml-backend.cpp
    ${LLAMA_CPP_DIR}/ggml/src/ggml-threading.cpp
    ${LLAMA_CPP_DIR}/ggml/src/ggml-opt.cpp
    ${LLAMA_CPP_DIR}/ggml/src/gguf.cpp
)

# GGML CPU backend sources
file(GLOB GGML_CPU_SOURCES
    "${LLAMA_CPP_DIR}/ggml/src/ggml-cpu/*.c"
    "${LLAMA_CPP_DIR}/ggml/src/ggml-cpu/*.cpp"
)

# GGML CPU llamafile sources (optimized GEMM)
file(GLOB GGML_LLAMAFILE_SOURCES
    "${LLAMA_CPP_DIR}/ggml/src/ggml-cpu/llamafile/*.cpp"
)

# ARM-specific sources for Android ARM64
if(${ANDROID_ABI} STREQUAL "arm64-v8a")
    file(GLOB GGML_ARM_SOURCES
        "${LLAMA_CPP_DIR}/ggml/src/ggml-cpu/arch/arm/*.c"
        "${LLAMA_CPP_DIR}/ggml/src/ggml-cpu/arch/arm/*.cpp"
    )
endif()

# ============================================================================
# CUSTOM BACKEND REGISTRY - Replaces ggml-backend-reg.cpp to avoid dynamic loading
# ============================================================================

# Create a custom backend registry that statically registers CPU backend only
set(CUSTOM_BACKEND_REG_FILE "${CMAKE_BINARY_DIR}/ggml-backend-reg-static.cpp")
file(WRITE ${CUSTOM_BACKEND_REG_FILE} "
// Static backend registry for Android - CPU only, no dynamic loading
// This replaces ggml-backend-reg.cpp to avoid std::filesystem ABI issues

#include \"ggml-backend.h\"
#include \"ggml-backend-impl.h\"
#include \"ggml-cpu.h\"

#include <vector>
#include <string>
#include <memory>
#include <mutex>

// Forward declaration
extern \"C\" ggml_backend_reg_t ggml_backend_cpu_reg(void);

// Static backend registry
static std::vector<ggml_backend_reg_t> g_backends;
static std::vector<ggml_backend_dev_t> g_devices;
static std::once_flag g_init_flag;

static void init_backends() {
    // Register CPU backend
    ggml_backend_reg_t cpu_reg = ggml_backend_cpu_reg();
    if (cpu_reg) {
        g_backends.push_back(cpu_reg);
        
        // Get devices from CPU backend
        size_t dev_count = ggml_backend_reg_dev_count(cpu_reg);
        for (size_t i = 0; i < dev_count; i++) {
            ggml_backend_dev_t dev = ggml_backend_reg_dev_get(cpu_reg, i);
            if (dev) {
                g_devices.push_back(dev);
            }
        }
    }
}

extern \"C\" {

size_t ggml_backend_reg_count(void) {
    std::call_once(g_init_flag, init_backends);
    return g_backends.size();
}

ggml_backend_reg_t ggml_backend_reg_get(size_t index) {
    std::call_once(g_init_flag, init_backends);
    if (index >= g_backends.size()) return nullptr;
    return g_backends[index];
}

ggml_backend_reg_t ggml_backend_reg_by_name(const char * name) {
    std::call_once(g_init_flag, init_backends);
    for (auto reg : g_backends) {
        if (strcmp(ggml_backend_reg_name(reg), name) == 0) {
            return reg;
        }
    }
    return nullptr;
}

size_t ggml_backend_dev_count(void) {
    std::call_once(g_init_flag, init_backends);
    return g_devices.size();
}

ggml_backend_dev_t ggml_backend_dev_get(size_t index) {
    std::call_once(g_init_flag, init_backends);
    if (index >= g_devices.size()) return nullptr;
    return g_devices[index];
}

ggml_backend_dev_t ggml_backend_dev_by_name(const char * name) {
    std::call_once(g_init_flag, init_backends);
    for (auto dev : g_devices) {
        if (strcmp(ggml_backend_dev_name(dev), name) == 0) {
            return dev;
        }
    }
    return nullptr;
}

ggml_backend_dev_t ggml_backend_dev_by_type(enum ggml_backend_dev_type type) {
    std::call_once(g_init_flag, init_backends);
    for (auto dev : g_devices) {
        if (ggml_backend_dev_type(dev) == type) {
            return dev;
        }
    }
    return nullptr;
}

void ggml_backend_set_n_threads(ggml_backend_t backend, int n_threads) {
    // Implementation for CPU backend thread setting
    // This is typically backend-specific
}

// Stub functions for dynamic loading - not used in static build
void ggml_backend_load_all(void) {
    std::call_once(g_init_flag, init_backends);
}

void ggml_backend_load_all_from_path(const char * path) {
    (void)path;
    std::call_once(g_init_flag, init_backends);
}

ggml_backend_reg_t ggml_backend_load_best(const char * name, bool silent, const char * user_search_path) {
    (void)name;
    (void)silent;
    (void)user_search_path;
    std::call_once(g_init_flag, init_backends);
    return g_backends.empty() ? nullptr : g_backends[0];
}

// Initialize a backend by device type
ggml_backend_t ggml_backend_init_by_type(enum ggml_backend_dev_type type, const char * params) {
    (void)params;
    std::call_once(g_init_flag, init_backends);
    
    // Find device by type and initialize backend
    for (auto dev : g_devices) {
        if (ggml_backend_dev_type(dev) == type) {
            return ggml_backend_dev_init(dev, params);
        }
    }
    return nullptr;
}

// Initialize a backend by name
ggml_backend_t ggml_backend_init_by_name(const char * name, const char * params) {
    std::call_once(g_init_flag, init_backends);
    
    ggml_backend_dev_t dev = ggml_backend_dev_by_name(name);
    if (dev) {
        return ggml_backend_dev_init(dev, params);
    }
    return nullptr;
}

} // extern \"C\"
")

# ============================================================================
# JNI WRAPPER - Exposes llama.cpp to Kotlin via JNI
# ============================================================================

set(JNI_WRAPPER_SOURCES
    ${CMAKE_SOURCE_DIR}/llama_jni.cpp
)

# ============================================================================
# COMBINE ALL SOURCES
# ============================================================================

set(ALL_SOURCES
    ${LLAMA_CORE_SOURCES}
    ${LLAMA_MODEL_SOURCES}
    ${GGML_CORE_SOURCES}
    ${GGML_CPU_SOURCES}
    ${GGML_LLAMAFILE_SOURCES}
    ${CUSTOM_BACKEND_REG_FILE}
    ${JNI_WRAPPER_SOURCES}
)

# Add ARM sources if on ARM64
if(${ANDROID_ABI} STREQUAL "arm64-v8a")
    list(APPEND ALL_SOURCES ${GGML_ARM_SOURCES})
endif()

# Remove the original ggml-backend-reg.cpp from sources (we use our static version)
list(FILTER ALL_SOURCES EXCLUDE REGEX ".*ggml-backend-reg\\.cpp$")

# ============================================================================
# INCLUDE DIRECTORIES
# ============================================================================

set(LLAMA_INCLUDES
    ${LLAMA_CPP_DIR}/include
    ${LLAMA_CPP_DIR}/src
    ${LLAMA_CPP_DIR}/ggml/include
    ${LLAMA_CPP_DIR}/ggml/src
    ${LLAMA_CPP_DIR}/ggml/src/ggml-cpu
    ${LLAMA_CPP_DIR}/ggml/src/ggml-cpu/arch
    ${LLAMA_CPP_DIR}/common
)

# ============================================================================
# BUILD LIBRARY
# ============================================================================

add_library(llama SHARED ${ALL_SOURCES})

target_include_directories(llama PRIVATE ${LLAMA_INCLUDES})

# Compiler definitions
target_compile_definitions(llama PRIVATE
    GGML_USE_CPU
    _GNU_SOURCE
    NDEBUG
    GGML_VERSION="0.0.0"
    GGML_COMMIT="android-embedded"
    # Disable features that require dynamic loading
    GGML_BACKEND_DL=0
)

# Link libraries
target_link_libraries(llama
    android
    log
    m
    dl
)

# Print source count for debugging
list(LENGTH ALL_SOURCES SOURCE_COUNT)
message(STATUS "llama.cpp: Building with ${SOURCE_COUNT} source files for ${ANDROID_ABI}")

# ============================================================================
# WHISPER.CPP (OPTIONAL) - Offline Speech-to-Text
# ============================================================================

set(WHISPER_CPP_DIR "${CMAKE_SOURCE_DIR}/../../../../../external/whisper.cpp")
set(WHISPER_JNI_SOURCES
    ${CMAKE_SOURCE_DIR}/whisper_jni.cpp
)

set(WHISPER_SOURCES
    ${WHISPER_JNI_SOURCES}
)

set(WHISPER_INCLUDES "")

set(WHISPER_HAS_ROOT_LAYOUT FALSE)
if (EXISTS "${WHISPER_CPP_DIR}/whisper.cpp" AND EXISTS "${WHISPER_CPP_DIR}/whisper.h")
    set(WHISPER_HAS_ROOT_LAYOUT TRUE)
endif()

set(WHISPER_HAS_INCLUDE_SRC_LAYOUT FALSE)
if (EXISTS "${WHISPER_CPP_DIR}/src/whisper.cpp" AND EXISTS "${WHISPER_CPP_DIR}/include/whisper.h")
    set(WHISPER_HAS_INCLUDE_SRC_LAYOUT TRUE)
endif()

if (WHISPER_HAS_ROOT_LAYOUT OR WHISPER_HAS_INCLUDE_SRC_LAYOUT)
    message(STATUS "whisper.cpp: Found sources at ${WHISPER_CPP_DIR}")

    # Whisper core
    file(GLOB WHISPER_CORE_SOURCES
        "${WHISPER_CPP_DIR}/*.c"
        "${WHISPER_CPP_DIR}/*.cpp"
        "${WHISPER_CPP_DIR}/src/*.c"
        "${WHISPER_CPP_DIR}/src/*.cpp"
    )

    # Whisper's ggml (repository layout differs across versions; include common paths)
    file(GLOB WHISPER_GGML_SOURCES
        "${WHISPER_CPP_DIR}/ggml/src/*.c"
        "${WHISPER_CPP_DIR}/ggml/src/*.cpp"
        "${WHISPER_CPP_DIR}/ggml/src/ggml-cpu/*.c"
        "${WHISPER_CPP_DIR}/ggml/src/ggml-cpu/*.cpp"
        "${WHISPER_CPP_DIR}/ggml/src/ggml-cpu/llamafile/*.cpp"
        "${WHISPER_CPP_DIR}/ggml/src/ggml-cpu/arch/arm/*.c"
        "${WHISPER_CPP_DIR}/ggml/src/ggml-cpu/arch/arm/*.cpp"
    )

    list(APPEND WHISPER_SOURCES ${WHISPER_CORE_SOURCES} ${WHISPER_GGML_SOURCES})

    set(WHISPER_INCLUDES
        ${WHISPER_CPP_DIR}
        ${WHISPER_CPP_DIR}/include
        ${WHISPER_CPP_DIR}/src
        ${WHISPER_CPP_DIR}/ggml/include
        ${WHISPER_CPP_DIR}/ggml/src
        ${WHISPER_CPP_DIR}/ggml/src/ggml-cpu
        ${WHISPER_CPP_DIR}/ggml/src/ggml-cpu/arch
    )
else()
    message(WARNING "whisper.cpp not found at ${WHISPER_CPP_DIR}. Building stub libwhisper.so (offline Whisper STT disabled).")
endif()

add_library(whisper SHARED ${WHISPER_SOURCES})

if (NOT "${WHISPER_INCLUDES}" STREQUAL "")
    target_include_directories(whisper PRIVATE ${WHISPER_INCLUDES})
endif()

target_compile_definitions(whisper PRIVATE
    _GNU_SOURCE
    WHISPER_VERSION="android-embedded"
    GGML_USE_CPU
    NDEBUG
    GGML_VERSION="0.0.0"
    GGML_COMMIT="android-embedded"
    GGML_BACKEND_DL=0
)

target_link_libraries(whisper
    android
    log
    m
)

list(LENGTH WHISPER_SOURCES WHISPER_SOURCE_COUNT)
message(STATUS "whisper.cpp: Building with ${WHISPER_SOURCE_COUNT} source files for ${ANDROID_ABI}")
