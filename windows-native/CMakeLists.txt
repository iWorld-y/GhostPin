cmake_minimum_required(VERSION 3.24)

project(GhostPinNative VERSION 0.1.0 LANGUAGES CXX RC)

if(NOT WIN32)
    message(FATAL_ERROR "GhostPin.Native 仅支持 Windows")
endif()

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

add_compile_options(/W4 /WX /permissive- /utf-8)
add_compile_definitions(UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)

set(NATIVE_INCLUDE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/src")

add_library(GhostPin.Native.Core STATIC
    src/core.cpp
    src/core.hpp
)
target_include_directories(GhostPin.Native.Core PUBLIC "${NATIVE_INCLUDE_DIR}")

add_library(GhostPin.Native.Platform STATIC
    src/raii.cpp
    src/raii.hpp
)
target_include_directories(GhostPin.Native.Platform PUBLIC "${NATIVE_INCLUDE_DIR}")
target_link_libraries(GhostPin.Native.Platform PUBLIC ole32 user32 gdi32)

add_library(GhostPin.Native.Storage STATIC
    src/codec.cpp
    src/codec.hpp
)
set_target_properties(GhostPin.Native.Storage PROPERTIES
    CXX_STANDARD 17
    CXX_STANDARD_REQUIRED ON
    CXX_EXTENSIONS OFF
)
target_include_directories(GhostPin.Native.Storage PUBLIC "${NATIVE_INCLUDE_DIR}")
target_compile_options(GhostPin.Native.Storage PRIVATE /await /permissive)
target_link_libraries(GhostPin.Native.Storage PUBLIC GhostPin.Native.Core)
target_link_libraries(GhostPin.Native.Storage PRIVATE runtimeobject)

add_library(GhostPin.Native.StoragePaths STATIC
    src/storage_paths.cpp
    src/storage_paths.hpp
)
set_target_properties(GhostPin.Native.StoragePaths PROPERTIES
    CXX_STANDARD 20
    CXX_STANDARD_REQUIRED ON
    CXX_EXTENSIONS OFF
)
target_include_directories(GhostPin.Native.StoragePaths PUBLIC "${NATIVE_INCLUDE_DIR}")
target_link_libraries(GhostPin.Native.StoragePaths PUBLIC shell32 ole32)

add_library(GhostPin.Native.Repository STATIC
    src/atomic_file.cpp
    src/atomic_file.hpp
    src/repository.cpp
    src/repository.hpp
)
set_target_properties(GhostPin.Native.Repository PROPERTIES
    CXX_STANDARD 20
    CXX_STANDARD_REQUIRED ON
    CXX_EXTENSIONS OFF
)
target_include_directories(GhostPin.Native.Repository PUBLIC "${NATIVE_INCLUDE_DIR}")
target_link_libraries(GhostPin.Native.Repository PUBLIC GhostPin.Native.Core GhostPin.Native.Storage)

add_library(GhostPin.Native.App STATIC
    src/app.cpp
    src/app.hpp
)
target_include_directories(GhostPin.Native.App PUBLIC "${NATIVE_INCLUDE_DIR}")
target_link_libraries(GhostPin.Native.App PUBLIC GhostPin.Native.Core GhostPin.Native.Platform user32)

add_executable(GhostPin.Native.CoreChecks src/core_checks.cpp)
target_link_libraries(GhostPin.Native.CoreChecks PRIVATE GhostPin.Native.Core)

add_executable(GhostPin.Native.PlatformChecks src/platform_checks.cpp)
target_link_libraries(GhostPin.Native.PlatformChecks PRIVATE GhostPin.Native.Platform)

add_executable(GhostPin.Native.JsonChecks src/codec_checks.cpp)
target_link_libraries(GhostPin.Native.JsonChecks PRIVATE GhostPin.Native.Storage)

add_executable(GhostPin.Native.StoragePathsChecks src/storage_paths_checks.cpp)
target_link_libraries(GhostPin.Native.StoragePathsChecks PRIVATE GhostPin.Native.StoragePaths)

add_executable(GhostPin.Native.RepositoryChecks src/repository_checks.cpp)
target_link_libraries(GhostPin.Native.RepositoryChecks PRIVATE GhostPin.Native.Repository)

set(NATIVE_FIXTURE_SOURCE_DIR
    "${CMAKE_CURRENT_SOURCE_DIR}/../windows/tests/GhostPin.Windows.Core.Tests/Fixtures")
set(NATIVE_FIXTURE_BINARY_DIR "${CMAKE_CURRENT_BINARY_DIR}/tests")
file(MAKE_DIRECTORY "${NATIVE_FIXTURE_BINARY_DIR}")
configure_file(
    "${NATIVE_FIXTURE_SOURCE_DIR}/tasks-cross-language.json"
    "${NATIVE_FIXTURE_BINARY_DIR}/tasks-cross-language.json"
    COPYONLY
)
configure_file(
    "${NATIVE_FIXTURE_SOURCE_DIR}/tasks-legacy-missing-status.json"
    "${NATIVE_FIXTURE_BINARY_DIR}/tasks-legacy-missing-status.json"
    COPYONLY
)

add_executable(GhostPin.Native WIN32
    src/main.cpp
    resources/GhostPin.rc
)
target_link_libraries(GhostPin.Native PRIVATE GhostPin.Native.App)
set_target_properties(GhostPin.Native PROPERTIES OUTPUT_NAME "GhostPin.Native")
set_target_properties(GhostPin.Native PROPERTIES LINK_FLAGS "/MANIFEST:NO")

enable_testing()
add_test(NAME GhostPin.Native.CoreChecks COMMAND GhostPin.Native.CoreChecks)
add_test(NAME GhostPin.Native.PlatformChecks COMMAND GhostPin.Native.PlatformChecks)
set_tests_properties(GhostPin.Native.PlatformChecks PROPERTIES SKIP_RETURN_CODE 77)
add_test(NAME GhostPin.Native.JsonChecks
    COMMAND GhostPin.Native.JsonChecks "${NATIVE_FIXTURE_BINARY_DIR}")
add_test(NAME GhostPin.Native.StoragePathsChecks COMMAND GhostPin.Native.StoragePathsChecks)
add_test(NAME GhostPin.Native.RepositoryChecks
    COMMAND GhostPin.Native.RepositoryChecks "${NATIVE_FIXTURE_BINARY_DIR}")
