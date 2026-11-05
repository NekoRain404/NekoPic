# Editable object tools: document-controller integration and its test.
# Included by the parent CMakeLists.txt after nekopic_app exists. This fragment
# runs before include(CTest) defines BUILD_TESTING, so the test is registered at
# the end of directory processing (same pattern as NekoPicObjects.cmake).

target_sources(nekopic_app PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/src/app/documentcontroller_objects.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/app/documentcontroller.h"
)

function(nekopic_register_objecttools_test)
    if(NOT BUILD_TESTING)
        return()
    endif()

    add_executable(objecttools_test "${CMAKE_CURRENT_SOURCE_DIR}/tests/tst_objecttools.cpp")
    target_link_libraries(objecttools_test PRIVATE nekopic_app Qt6::Test)
    add_test(NAME objecttools COMMAND objecttools_test)
    set_tests_properties(objecttools PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
endfunction()

cmake_language(DEFER CALL nekopic_register_objecttools_test)
