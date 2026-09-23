cmake_minimum_required(VERSION 3.20)
project(CafeinaWorldCore LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

add_library(cafeina_world_core STATIC
    src/World.cpp
)
target_include_directories(cafeina_world_core PUBLIC include)

enable_testing()
add_executable(cafeina_world_core_smoke tests/world_smoke.cpp)
target_link_libraries(cafeina_world_core_smoke PRIVATE cafeina_world_core)
add_test(NAME cafeina_world_core_smoke COMMAND cafeina_world_core_smoke)
