# Build-time feature switches. Defaults keep the shipped product C++-only.
option(NEKOPIC_WITH_RUST "Build optional Rust codec/metadata module (ADR-0002)" OFF)
option(NEKOPIC_BUILD_QML_TESTS "Register QML interaction tests with CTest" OFF)
