# Settings module: persisted preferences and the settings-page test.
# Included by the parent CMakeLists.txt after nekopic_app exists. This fragment
# runs before include(CTest) defines BUILD_TESTING, so the test is registered at
# the end of directory processing (same pattern as NekoPicObjects.cmake).

target_sources(nekopic_app PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/src/app/settingsmanager.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/app/settingsmanager.h"
)

function(nekopic_register_settingsmanager_test)
    if(NOT BUILD_TESTING)
        return()
    endif()

    add_executable(settingsmanager_test "${CMAKE_CURRENT_SOURCE_DIR}/tests/tst_settingsmanager.cpp")
    target_link_libraries(settingsmanager_test PRIVATE nekopic_app Qt6::Test)
    add_test(NAME settingsmanager COMMAND settingsmanager_test)
    set_tests_properties(settingsmanager PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
endfunction()

cmake_language(DEFER CALL nekopic_register_settingsmanager_test)
