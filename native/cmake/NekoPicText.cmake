# Styled-text command layer and its standalone test. The parent CMakeLists
# includes this fragment after nekopic_app exists but before include(CTest)
# defines BUILD_TESTING, so the test target is registered at the end of
# directory processing (same pattern as NekoPicObjects.cmake).

target_sources(nekopic_app PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/src/app/documentcontroller_text.cpp")

function(nekopic_register_textcommands_test)
    if(NOT BUILD_TESTING)
        return()
    endif()

    add_executable(textcommands_test "${CMAKE_CURRENT_SOURCE_DIR}/tests/tst_textcommands.cpp")
    target_link_libraries(textcommands_test PRIVATE nekopic_app Qt6::Test)
    add_test(NAME textcommands COMMAND textcommands_test)
    set_tests_properties(textcommands PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
endfunction()

cmake_language(DEFER CALL nekopic_register_textcommands_test)
