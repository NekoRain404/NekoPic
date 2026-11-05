# Extended colour pipeline standalone test.
# The pipeline translation units are part of nekopic_core; see the core source
# list in native/CMakeLists.txt. This module only owns the standalone test.
# Included by the parent CMakeLists.txt after nekopic_core exists.

# The fragment is included before include(CTest) defines BUILD_TESTING, so
# register the test at the end of directory processing when that option and
# Qt6::Test are available.
function(nekopic_register_color_test)
    if(NOT BUILD_TESTING)
        return()
    endif()

    add_executable(colorpipeline_test "${CMAKE_CURRENT_SOURCE_DIR}/tests/tst_colorpipeline.cpp")
    target_link_libraries(colorpipeline_test PRIVATE nekopic_core Qt6::Test)
    add_test(NAME colorpipeline COMMAND colorpipeline_test)
    set_tests_properties(colorpipeline PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
endfunction()

cmake_language(DEFER CALL nekopic_register_color_test)
