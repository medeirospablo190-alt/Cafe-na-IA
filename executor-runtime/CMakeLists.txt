cmake_minimum_required(VERSION 3.20)
project(CafeinaLuauRuntime LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

include(FetchContent)

option(
    CAFEINA_ENABLE_LOCAL_LLM
    "Build the experimental local LLM compile/link probe"
    OFF
)

set(LUAU_BUILD_CLI OFF CACHE BOOL "" FORCE)
set(LUAU_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(LUAU_BUILD_WEB OFF CACHE BOOL "" FORCE)

FetchContent_Declare(
    luau
    GIT_REPOSITORY https://github.com/luau-lang/luau.git
    GIT_TAG 653fa9cb7a6b379651292ce1b7e4649b6e12ab02
    GIT_SHALLOW FALSE
)
FetchContent_MakeAvailable(luau)

add_library(cafeina_luau_runtime STATIC
    src/LuauRuntime.cpp
)
target_include_directories(cafeina_luau_runtime PUBLIC include)
target_link_libraries(cafeina_luau_runtime PUBLIC Luau.VM Luau.Compiler)

if(ANDROID)
    add_library(cafeina_luau_jni SHARED src/android_jni.cpp)
    target_link_libraries(cafeina_luau_jni PRIVATE cafeina_luau_runtime)

    if(CAFEINA_ENABLE_LOCAL_LLM)
        # First compile/link experiment only. No model is bundled and this
        # target is absent from normal builds unless explicitly enabled.
        set(LLAMA_BUILD_COMMON OFF CACHE BOOL "" FORCE)
        set(LLAMA_BUILD_TESTS OFF CACHE BOOL "" FORCE)
        set(LLAMA_BUILD_TOOLS OFF CACHE BOOL "" FORCE)
        set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
        set(LLAMA_BUILD_SERVER OFF CACHE BOOL "" FORCE)
        set(LLAMA_BUILD_APP OFF CACHE BOOL "" FORCE)
        set(LLAMA_BUILD_UI OFF CACHE BOOL "" FORCE)
        set(GGML_NATIVE OFF CACHE BOOL "" FORCE)
        set(GGML_OPENMP OFF CACHE BOOL "" FORCE)

        FetchContent_Declare(
            llama_cpp
            GIT_REPOSITORY https://github.com/ggml-org/llama.cpp.git
            # llama.cpp b11312, resolved on 2026-10-01.
            GIT_TAG 0c1e57098bba43ac29e6e3b677cdceebdd22334f
            GIT_SHALLOW FALSE
        )
        FetchContent_MakeAvailable(llama_cpp)

        add_library(cafeina_llm_probe SHARED src/llm_probe.cpp)
        target_link_libraries(
            cafeina_llm_probe
            PRIVATE
                llama
                android
                log
        )

        add_library(cafeina_llama_jni SHARED src/llm_android_jni.cpp)
        target_link_libraries(
            cafeina_llama_jni
            PRIVATE
                llama
                android
                log
        )
    endif()
else()
    add_executable(cafeina_luau_cli src/main.cpp)
    target_link_libraries(cafeina_luau_cli PRIVATE cafeina_luau_runtime)

    enable_testing()
    add_executable(cafeina_luau_runtime_smoke tests/runtime_smoke.cpp)
    target_link_libraries(cafeina_luau_runtime_smoke PRIVATE cafeina_luau_runtime)
    add_test(NAME cafeina_luau_runtime_smoke COMMAND cafeina_luau_runtime_smoke)
endif()
