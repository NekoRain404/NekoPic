# NekoPic Native First Milestone

**Goal:** A runnable Qt Quick desktop shell with asynchronous image opening, viewing, and safe PNG/JPEG export, preserving the HTML prototype.

**Architecture:** QML binds to a GUI-thread document controller. Image decoding and encoding run off-thread through a focused image I/O module. A Qt Quick image provider transfers the current decoded image into the scene graph. The shell does not depend on codec internals.

**Stack:** C++20, Qt 6 Quick, Quick Controls, Concurrent, Test and CMake. No Rust dependency until a suitable independent component exists.

**Parallel ownership:** `native/qml/` is owned by the UI task; `native/src/core/` and `native/tests/` by image I/O; `native/docs/architecture.md` by architecture; integration owns CMake, controller and application entry point. Existing H5 files remain untouched.

**Acceptance:** Build with warnings; verify image load failures and atomic export with tests; run the application with real Qt Quick; explicitly distinguish unimplemented editing, ICC pipeline, metadata preservation, extra codecs and GPU image processing from functioning features.

**Quality:** Decode within defined limits, apply image orientation, preserve decoded representation when possible, explicitly composite transparent pixels for JPEG. Never clear dirty state on failed save. Import/export behavior beyond Qt codec capabilities is not promised.
