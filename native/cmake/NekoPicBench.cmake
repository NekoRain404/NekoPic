# Optional benchmark module. The root CMakeLists includes this file when it
# exists, so the benchmark stays opt-in without editing the integration file.
#
# Build:  cmake --build <build-dir> --target bench_pipeline
# Run:    <build-dir>/bench_pipeline
#         <build-dir>/bench_pipeline --quick
#
# This target is deliberately NOT registered with CTest: it takes tens of
# seconds and its numbers depend on the host. To expose a smoke gate anyway,
# uncomment the following lines (and set a generous timeout):
#
#   add_test(NAME bench_pipeline_smoke COMMAND bench_pipeline --quick)
#   set_tests_properties(bench_pipeline_smoke PROPERTIES TIMEOUT 300)

add_executable(bench_pipeline tests/bench_pipeline.cpp)
target_include_directories(bench_pipeline PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src")
target_link_libraries(bench_pipeline PRIVATE
    nekopic_core
    nekopic_document
    nekopic_io
    nekopic_render
    Qt6::Core
    Qt6::Gui
    Qt6::Concurrent)
# The demo decode path is resolved from the source tree; timings never read
# any other file from disk.
target_compile_definitions(bench_pipeline PRIVATE
    NEKOPIC_BENCH_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_options(bench_pipeline PRIVATE -Wall -Wextra -Wpedantic)

add_custom_target(bench
    COMMAND bench_pipeline
    DEPENDS bench_pipeline
    USES_TERMINAL
    COMMENT "Running NekoPic pipeline benchmark")
