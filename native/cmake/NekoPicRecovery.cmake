# Crash-recovery snapshots and their tests. Included by the parent
# CMakeLists.txt after nekopic_app exists but before include(CTest) defines
# BUILD_TESTING, so the test target is registered at the end of directory
# processing (same pattern as NekoPicSettings.cmake).

target_sources(nekopic_app PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/src/app/recoverystore.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/app/recoverystore.h"
)

function(nekopic_register_recoverystore_test)
    if(NOT BUILD_TESTING)
        return()
    endif()

    add_executable(recoverystore_test "${CMAKE_CURRENT_SOURCE_DIR}/tests/tst_recoverystore.cpp")
    target_link_libraries(recoverystore_test PRIVATE nekopic_app Qt6::Test)
    add_test(NAME recoverystore COMMAND recoverystore_test)
    set_tests_properties(recoverystore PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
endfunction()

cmake_language(DEFER CALL nekopic_register_recoverystore_test)
