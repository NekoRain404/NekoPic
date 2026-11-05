# Adds a C++ test executable and registers it with CTest.
# Usage: nekopic_add_test(<name> <source> <library>)
function(nekopic_add_test name source library)
    add_executable(${name}_test ${source})
    target_link_libraries(${name}_test PRIVATE ${library} Qt6::Test)
    add_test(NAME ${name} COMMAND ${name}_test)
    set_tests_properties(${name} PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
endfunction()
