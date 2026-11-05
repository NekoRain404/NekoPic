# Object model sources and its standalone test.
# Included by the parent CMakeLists.txt after nekopic_document exists.

target_sources(nekopic_document PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/src/document/object.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/document/object.h"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/document/textobject.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/document/textobject.h"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/document/shapeobject.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/document/shapeobject.h"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/document/strokeobject.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/document/strokeobject.h"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/document/objectlayer.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/document/objectlayer.h"
)

# This fragment is included before include(CTest) defines BUILD_TESTING, so
# register the test at the end of directory processing when that option and
# Qt6::Test are available.
function(nekopic_register_objects_test)
    if(NOT BUILD_TESTING)
        return()
    endif()

    add_executable(objects_test "${CMAKE_CURRENT_SOURCE_DIR}/tests/tst_objects.cpp")
    target_link_libraries(objects_test PRIVATE nekopic_document Qt6::Test)
    add_test(NAME objects COMMAND objects_test)
    set_tests_properties(objects PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
endfunction()

cmake_language(DEFER CALL nekopic_register_objects_test)
