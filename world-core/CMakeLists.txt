cmake_minimum_required(VERSION 3.20)
project(CafeinaWorldCore LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

option(CAFEINA_WORLD_BUILD_SERIALIZATION "Build JSON world persistence" ON)
option(CAFEINA_WORLD_BUILD_TESTS "Build World Core smoke tests" ON)

add_library(cafeina_world_core STATIC
    src/World.cpp
    src/WorldService.cpp
)
target_include_directories(cafeina_world_core PUBLIC include)

if(CAFEINA_WORLD_BUILD_SERIALIZATION)
    include(FetchContent)

    set(JSON_BuildTests OFF CACHE INTERNAL "")
    FetchContent_Declare(
        nlohmann_json
        URL https://github.com/nlohmann/json/releases/download/v3.12.0/json.tar.xz
        URL_HASH SHA256=42f6e95cad6ec532fd372391373363b62a14af6d771056dbfc86160e6dfff7aa
        DOWNLOAD_EXTRACT_TIMESTAMP TRUE
    )
    FetchContent_MakeAvailable(nlohmann_json)

    add_library(cafeina_world_serialization STATIC
        src/WorldSerialization.cpp
    )
    target_include_directories(cafeina_world_serialization PUBLIC include)
    target_link_libraries(
        cafeina_world_serialization
        PUBLIC cafeina_world_core nlohmann_json::nlohmann_json
    )
endif()

if(CAFEINA_WORLD_BUILD_TESTS)
    if(NOT CAFEINA_WORLD_BUILD_SERIALIZATION)
        message(FATAL_ERROR "World Core smoke tests currently require serialization")
    endif()

    find_package(Threads REQUIRED)
    enable_testing()

    add_executable(cafeina_world_core_smoke tests/world_smoke.cpp)
    target_link_libraries(
        cafeina_world_core_smoke
        PRIVATE cafeina_world_core cafeina_world_serialization Threads::Threads
    )
    add_test(NAME cafeina_world_core_smoke COMMAND cafeina_world_core_smoke)
endif()
