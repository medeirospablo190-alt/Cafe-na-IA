cmake_minimum_required(VERSION 3.20)
project(CafeinaRenderCore LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

set(CAFEINA_WORLD_BUILD_SERIALIZATION OFF)
set(CAFEINA_WORLD_BUILD_TESTS OFF)
add_subdirectory(
    "${CMAKE_CURRENT_SOURCE_DIR}/../world-core"
    "${CMAKE_CURRENT_BINARY_DIR}/world-core"
)

add_library(cafeina_render_core STATIC
    src/RenderScene.cpp
    src/RenderPicking.cpp
)
target_include_directories(cafeina_render_core PUBLIC include)
target_link_libraries(cafeina_render_core PUBLIC cafeina_world_core)

enable_testing()
add_executable(cafeina_render_core_smoke tests/render_scene_smoke.cpp)
target_link_libraries(cafeina_render_core_smoke PRIVATE cafeina_render_core)
add_test(NAME cafeina_render_core_smoke COMMAND cafeina_render_core_smoke)
