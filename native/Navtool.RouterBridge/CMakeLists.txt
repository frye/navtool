cmake_minimum_required(VERSION 3.20)

project(NavtoolRouterBridge VERSION 1.0.0 LANGUAGES C CXX)

option(NAVTOOL_ROUTER_BRIDGE_BUILD_TESTS "Build native bridge tests" ON)
set(
    SAILROUTE_SOURCE_DIR
    ""
    CACHE PATH
    "Optional path to a router-lib source tree override")
set(
    NAVTOOL_ROUTER_LIB_RELEASE_REPOSITORY
    "https://github.com/frye/router-lib.git"
    CACHE STRING
    "router-lib release repository used when SAILROUTE_SOURCE_DIR is unset")
set(
    NAVTOOL_ROUTER_LIB_RELEASE_TAG
    "v0.1.1"
    CACHE STRING
    "router-lib release tag used when SAILROUTE_SOURCE_DIR is unset")
set(_navtool_router_effective_source_dir "")

if(NOT TARGET sailroute::sailroute)
    if(DEFINED SAILROUTE_SOURCE_DIR AND NOT "${SAILROUTE_SOURCE_DIR}" STREQUAL "")
        if(NOT EXISTS "${SAILROUTE_SOURCE_DIR}/CMakeLists.txt")
            message(
                FATAL_ERROR
                "router-lib not found. Set SAILROUTE_SOURCE_DIR to its source directory.")
        endif()
        set(_navtool_router_effective_source_dir "${SAILROUTE_SOURCE_DIR}")
        set(SAILROUTE_BUILD_TESTS OFF CACHE BOOL "" FORCE)
        set(SAILROUTE_BUILD_BENCHMARKS OFF CACHE BOOL "" FORCE)
        add_subdirectory(
            "${SAILROUTE_SOURCE_DIR}"
            "${CMAKE_CURRENT_BINARY_DIR}/router-lib"
            EXCLUDE_FROM_ALL)
    else()
        include(FetchContent)
        set(SAILROUTE_BUILD_TESTS OFF CACHE BOOL "" FORCE)
        set(SAILROUTE_BUILD_BENCHMARKS OFF CACHE BOOL "" FORCE)
        FetchContent_Declare(
            sailroute
            GIT_REPOSITORY "${NAVTOOL_ROUTER_LIB_RELEASE_REPOSITORY}"
            GIT_TAG "${NAVTOOL_ROUTER_LIB_RELEASE_TAG}"
            GIT_SHALLOW ON)
        FetchContent_MakeAvailable(sailroute)
        if(NOT TARGET sailroute::sailroute)
            message(
                FATAL_ERROR
                "Failed to load router-lib from ${NAVTOOL_ROUTER_LIB_RELEASE_REPOSITORY} at ${NAVTOOL_ROUTER_LIB_RELEASE_TAG}.")
        endif()
        if(DEFINED sailroute_SOURCE_DIR)
            set(_navtool_router_effective_source_dir "${sailroute_SOURCE_DIR}")
        endif()
    endif()
elseif(DEFINED SAILROUTE_SOURCE_DIR AND NOT "${SAILROUTE_SOURCE_DIR}" STREQUAL "")
    set(_navtool_router_effective_source_dir "${SAILROUTE_SOURCE_DIR}")
endif()

if(TARGET sailroute)
    set_target_properties(
        sailroute
        PROPERTIES
            POSITION_INDEPENDENT_CODE ON
            CXX_VISIBILITY_PRESET hidden
            VISIBILITY_INLINES_HIDDEN YES)
endif()

# Ensure ECCODES::eccodes is available for the inspection API.
# It is defined by the sailroute subdirectory; guard against the edge case
# where this bridge is added to a build that already found ecCodes directly.
if(NOT TARGET ECCODES::eccodes)
    find_package(eccodes CONFIG QUIET)
    if(NOT TARGET eccodes AND NOT TARGET eccodes_shared AND NOT TARGET ECCODES::eccodes)
        find_package(PkgConfig REQUIRED)
        pkg_check_modules(ECCODES REQUIRED IMPORTED_TARGET eccodes)
        add_library(ECCODES::eccodes ALIAS PkgConfig::ECCODES)
    elseif(TARGET eccodes AND NOT TARGET ECCODES::eccodes)
        add_library(ECCODES::eccodes ALIAS eccodes)
    elseif(TARGET eccodes_shared AND NOT TARGET ECCODES::eccodes)
        add_library(ECCODES::eccodes ALIAS eccodes_shared)
    endif()
endif()

add_library(NavtoolRouterBridge SHARED
    src/navtool_router_bridge.cpp)
add_library(Navtool::RouterBridge ALIAS NavtoolRouterBridge)

file(
    GLOB_RECURSE
    _navtool_router_public_headers
    "${_navtool_router_effective_source_dir}/include/*.hpp")
set(_navtool_router_has_progress_callback OFF)
foreach(_navtool_router_header IN LISTS _navtool_router_public_headers)
    file(READ "${_navtool_router_header}" _navtool_router_header_contents)
    if(_navtool_router_header_contents MATCHES "RoutingProgressCallback")
        set(_navtool_router_has_progress_callback ON)
        break()
    endif()
endforeach()

target_compile_features(NavtoolRouterBridge PRIVATE cxx_std_20)
target_compile_definitions(
    NavtoolRouterBridge
    PRIVATE
        NAVTOOL_ROUTER_BRIDGE_BUILDING
        NAVTOOL_ROUTER_HAS_PROGRESS_CALLBACK=$<BOOL:${_navtool_router_has_progress_callback}>)
target_include_directories(
    NavtoolRouterBridge
    PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>)
target_link_libraries(
    NavtoolRouterBridge
    PRIVATE sailroute::sailroute ECCODES::eccodes)
set_target_properties(
    NavtoolRouterBridge
    PROPERTIES
        CXX_VISIBILITY_PRESET hidden
        VISIBILITY_INLINES_HIDDEN YES
        VERSION ${PROJECT_VERSION}
        SOVERSION ${PROJECT_VERSION_MAJOR}
        OUTPUT_NAME navtool_router_bridge)

if(MSVC)
    target_compile_options(NavtoolRouterBridge PRIVATE /W4 /permissive-)
else()
    target_compile_options(
        NavtoolRouterBridge
        PRIVATE -Wall -Wextra -Wpedantic -Wconversion -Wshadow)
endif()

if(NAVTOOL_ROUTER_BRIDGE_BUILD_TESTS)
    enable_testing()
    add_executable(
        navtool_router_bridge_tests
        tests/bridge_tests.cpp)
    target_compile_features(navtool_router_bridge_tests PRIVATE cxx_std_20)
    target_compile_definitions(
        navtool_router_bridge_tests
        PRIVATE
            NAVTOOL_ROUTER_HAS_PROGRESS_CALLBACK=$<BOOL:${_navtool_router_has_progress_callback}>
            NAVTOOL_ROUTER_SAMPLE_GRIB="${_navtool_router_effective_source_dir}/samples/sample.grib")
    target_link_libraries(
        navtool_router_bridge_tests
        PRIVATE Navtool::RouterBridge ECCODES::eccodes)
    add_test(
        NAME navtool_router_bridge_tests
        COMMAND navtool_router_bridge_tests)
endif()
