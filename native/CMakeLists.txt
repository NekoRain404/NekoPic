cmake_minimum_required(VERSION 3.21)
project(NekoPic VERSION 0.1.0 LANGUAGES CXX)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")
include(NekoPicOptions)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_AUTOMOC ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2 Concurrent)
qt_standard_project_setup()

# --- core: framework-light image algorithms -------------------------------
add_library(nekopic_core STATIC
    src/core/adjustments.cpp src/core/adjustments.h
    src/core/mosaic.cpp src/core/mosaic.h)
target_include_directories(nekopic_core PUBLIC src src/core)
target_link_libraries(nekopic_core PUBLIC Qt6::Core Qt6::Gui)

# --- io: decode/encode, format capabilities -------------------------------
add_library(nekopic_io STATIC
    src/io/imageio.cpp src/io/imageio.h
    src/io/formatregistry.cpp src/io/formatregistry.h)
target_include_directories(nekopic_io PUBLIC src)
target_link_libraries(nekopic_io PUBLIC nekopic_core)

# --- document: state, transactions, history ------------------------------
add_library(nekopic_document STATIC
    src/document/history.cpp src/document/history.h)
target_include_directories(nekopic_document PUBLIC src)
target_link_libraries(nekopic_document PUBLIC nekopic_core)

# --- render: preview backends and GPU capability probes ------------------
add_library(nekopic_render STATIC
    src/render/rendercapabilities.cpp src/render/rendercapabilities.h)
target_include_directories(nekopic_render PUBLIC src)
target_link_libraries(nekopic_render PUBLIC nekopic_core Qt6::Quick)

# --- app: document controller and QML bridge -----------------------------
add_library(nekopic_app STATIC
    src/app/documentcontroller.cpp src/app/documentcontroller.h
    src/app/documentcontroller_mosaic.cpp src/app/documentcontroller_geometry.cpp
    src/app/filterpreviews.cpp src/app/filterpreviews.h
    src/app/languagemanager.cpp src/app/languagemanager.h)
target_include_directories(nekopic_app PUBLIC src)
target_link_libraries(nekopic_app PUBLIC nekopic_io nekopic_document nekopic_render
    Qt6::Concurrent Qt6::Quick Qt6::Qml)

qt_add_executable(nekopic src/app/main.cpp)
target_link_libraries(nekopic PRIVATE nekopic_app Qt6::Quick Qt6::Qml Qt6::QuickControls2)

file(GLOB_RECURSE NEKOPIC_QML CONFIGURE_DEPENDS RELATIVE "${CMAKE_CURRENT_SOURCE_DIR}" "qml/*.qml")
list(FILTER NEKOPIC_QML EXCLUDE REGEX "^qml/tests/")
file(GLOB_RECURSE NEKOPIC_QMLDIR CONFIGURE_DEPENDS RELATIVE "${CMAKE_CURRENT_SOURCE_DIR}" "qml/**/qmldir")
qt_add_resources(nekopic qml_resources PREFIX "/" FILES ${NEKOPIC_QML} ${NEKOPIC_QMLDIR})

# --- shaders (compiled to .qsb for ShaderEffect) -------------------------
file(GLOB_RECURSE NEKOPIC_SHADERS CONFIGURE_DEPENDS RELATIVE "${CMAKE_CURRENT_SOURCE_DIR}" "shaders/*.frag")
if(NEKOPIC_SHADERS)
    find_package(Qt6 QUIET COMPONENTS ShaderTools)
    if(COMMAND qt_add_shaders)
        qt_add_shaders(nekopic "nekopic_shaders" PREFIX "/shaders" FILES ${NEKOPIC_SHADERS})
    else()
        message(FATAL_ERROR "Shader sources found but Qt ShaderTools is unavailable")
    endif()
endif()

find_program(QT_LRELEASE NAMES lrelease HINTS "${QT6_INSTALL_PREFIX}/lib/qt6/bin" /usr/lib/qt6/bin REQUIRED)
set(NEKOPIC_QM "${CMAKE_CURRENT_BINARY_DIR}/nekopic_zh_CN.qm")
add_custom_command(OUTPUT "${NEKOPIC_QM}"
    COMMAND "${QT_LRELEASE}" "${CMAKE_CURRENT_SOURCE_DIR}/i18n/nekopic_zh_CN.ts" -qm "${NEKOPIC_QM}"
    DEPENDS i18n/nekopic_zh_CN.ts VERBATIM)
set_source_files_properties("${NEKOPIC_QM}" PROPERTIES QT_RESOURCE_ALIAS "nekopic_zh_CN.qm")
qt_add_resources(nekopic_app translations PREFIX "/i18n" FILES "${NEKOPIC_QM}")

foreach(target nekopic_core nekopic_io nekopic_document nekopic_render nekopic_app nekopic)
    target_compile_options(${target} PRIVATE -Wall -Wextra -Wpedantic)
endforeach()

# Optional feature modules may contribute sources, targets or tests without
# forcing every workstream to edit this integration file.
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/cmake/NekoPicRender.cmake")
    include(NekoPicRender)
endif()
if(NEKOPIC_WITH_RUST AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/cmake/NekoPicRust.cmake")
    include(NekoPicRust)
endif()

include(CTest)
if(BUILD_TESTING)
    find_package(Qt6 6.5 REQUIRED COMPONENTS Test)
    include(NekoPicTests)
    nekopic_add_test(imageio tests/tst_imageio.cpp nekopic_io)
    nekopic_add_test(adjustments tests/tst_adjustments.cpp nekopic_core)
    nekopic_add_test(mosaic tests/tst_mosaic.cpp nekopic_core)
    nekopic_add_test(history tests/tst_history.cpp nekopic_document)
    nekopic_add_test(formatregistry tests/tst_formatregistry.cpp nekopic_io)
    nekopic_add_test(documentcontroller tests/documentcontroller_test.cpp nekopic_app)
    nekopic_add_test(crop tests/tst_crop.cpp nekopic_app)
    nekopic_add_test(filterpreviews tests/tst_filterpreviews.cpp nekopic_app)
    nekopic_add_test(previewcontract tests/tst_previewcontract.cpp nekopic_app)
    nekopic_add_test(languagemanager tests/tst_languagemanager.cpp nekopic_app)
    if(NEKOPIC_WITH_RUST)
        nekopic_add_test(rustcodecs tests/tst_rustcodecs.cpp nekopic_io)
    endif()
endif()
