# Privacy blur module. The parent CMakeLists includes this fragment when it is
# present, before include(CTest) defines BUILD_TESTING, so the test target is
# registered at the end of directory processing.

target_sources(nekopic_core PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/src/core/blur.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/core/blur.h")

function(nekopic_register_blur_test)
    if(NOT BUILD_TESTING)
        return()
    endif()

    add_executable(blur_test "${CMAKE_CURRENT_SOURCE_DIR}/tests/tst_blur.cpp")
    target_link_libraries(blur_test PRIVATE nekopic_core Qt6::Test)
    add_test(NAME blur COMMAND blur_test)
    set_tests_properties(blur PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
endfunction()

cmake_language(DEFER CALL nekopic_register_blur_test)
