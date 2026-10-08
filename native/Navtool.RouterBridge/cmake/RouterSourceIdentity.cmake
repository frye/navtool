function(navtool_read_source_identity source_directory revision_output dirty_output)
    set(_revision "unknown")
    set(_dirty "unknown")
    find_package(Git REQUIRED)
    execute_process(COMMAND "${GIT_EXECUTABLE}" rev-parse --show-toplevel
        WORKING_DIRECTORY "${source_directory}"
        OUTPUT_VARIABLE _git_root OUTPUT_STRIP_TRAILING_WHITESPACE
        RESULT_VARIABLE _root_result ERROR_QUIET)
    file(REAL_PATH "${source_directory}" _source_root)
    if(_root_result EQUAL 0)
        file(REAL_PATH "${_git_root}" _git_root)
    endif()
    # Git walks into parent repositories for source archives extracted inside Navtool.
    if(_root_result EQUAL 0 AND "${_git_root}" STREQUAL "${_source_root}")
        execute_process(COMMAND "${GIT_EXECUTABLE}" rev-parse HEAD
            WORKING_DIRECTORY "${source_directory}"
            OUTPUT_VARIABLE _head OUTPUT_STRIP_TRAILING_WHITESPACE
            RESULT_VARIABLE _head_result ERROR_QUIET)
        if(_head_result EQUAL 0)
            set(_revision "${_head}")
            execute_process(COMMAND "${GIT_EXECUTABLE}" status --porcelain
                WORKING_DIRECTORY "${source_directory}"
                OUTPUT_VARIABLE _status RESULT_VARIABLE _status_result ERROR_QUIET)
            if(_status_result EQUAL 0)
                if("${_status}" STREQUAL "")
                    set(_dirty "false")
                else()
                    set(_dirty "true")
                endif()
            endif()
        endif()
    endif()
    set("${revision_output}" "${_revision}" PARENT_SCOPE)
    set("${dirty_output}" "${_dirty}" PARENT_SCOPE)
endfunction()
