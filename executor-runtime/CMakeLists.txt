cmake_minimum_required(VERSION 3.20)
project(CafeinaLuauRuntime LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

include(FetchContent)

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

set(CAFEINA_WORLD_BUILD_SERIALIZATION OFF)
set(CAFEINA_WORLD_BUILD_TESTS OFF)
add_subdirectory(
    "${CMAKE_CURRENT_SOURCE_DIR}/../world-core"
    "${CMAKE_CURRENT_BINARY_DIR}/world-core"
)

add_library(cafeina_luau_runtime STATIC
    src/LuauRuntime.cpp
    src/WorldLuauApi.cpp
)
target_include_directories(cafeina_luau_runtime PUBLIC include)
target_link_libraries(
    cafeina_luau_runtime
    PUBLIC Luau.VM Luau.Compiler cafeina_world_core
)

if(ANDROID)
    add_library(cafeina_luau_jni SHARED src/android_jni.cpp)
    target_link_libraries(cafeina_luau_jni PRIVATE cafeina_luau_runtime)
else()
    add_executable(cafeina_luau_cli src/main.cpp)
    target_link_libraries(cafeina_luau_cli PRIVATE cafeina_luau_runtime)

    enable_testing()
    find_package(Threads REQUIRED)
    add_executable(cafeina_luau_runtime_smoke tests/runtime_smoke.cpp)
    target_link_libraries(cafeina_luau_runtime_smoke PRIVATE cafeina_luau_runtime Threads::Threads)
    add_test(NAME cafeina_luau_runtime_smoke COMMAND cafeina_luau_runtime_smoke)
endif()
