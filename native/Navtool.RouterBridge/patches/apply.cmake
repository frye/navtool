# Applies the router-lib patches listed in NAVTOOL_ROUTER_LIB_PATCHES to the
# FetchContent source tree. Run as the FetchContent PATCH_COMMAND with the
# populated source directory as the working directory.
#
# Idempotent by design: FetchContent replays PATCH_COMMAND whenever it refreshes
# the source tree, and a tree that already carries a patch must not fail the
# build. Each patch is skipped when it reverse-applies cleanly (already present)
# and applied otherwise.

cmake_minimum_required(VERSION 3.20)

if(NOT DEFINED PATCH_DIR)
    message(FATAL_ERROR "PATCH_DIR was not provided to the router-lib patch step.")
endif()

if(NOT DEFINED PATCHES OR "${PATCHES}" STREQUAL "")
    return()
endif()

find_package(Git QUIET REQUIRED)
string(REPLACE "|" ";" _patches "${PATCHES}")

foreach(_patch IN LISTS _patches)
    set(_path "${PATCH_DIR}/${_patch}")
    if(NOT EXISTS "${_path}")
        message(FATAL_ERROR "router-lib patch not found: ${_path}")
    endif()

    execute_process(
        COMMAND "${GIT_EXECUTABLE}" apply --reverse --check "${_path}"
        RESULT_VARIABLE _already_applied
        OUTPUT_QUIET
        ERROR_QUIET)
    if(_already_applied EQUAL 0)
        message(STATUS "router-lib patch already applied: ${_patch}")
        continue()
    endif()

    execute_process(
        COMMAND "${GIT_EXECUTABLE}" apply "${_path}"
        RESULT_VARIABLE _apply_result
        ERROR_VARIABLE _apply_error)
    if(NOT _apply_result EQUAL 0)
        message(
            FATAL_ERROR
            "Failed to apply router-lib patch ${_patch}. The pinned revision may "
            "have moved past it; see native/Navtool.RouterBridge/patches/README.md.\n"
            "${_apply_error}")
    endif()
    message(STATUS "Applied router-lib patch: ${_patch}")
endforeach()
