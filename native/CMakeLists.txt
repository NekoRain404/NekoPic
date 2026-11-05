cmake_minimum_required(VERSION 3.21)
project(NekoPic VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_AUTOMOC ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2 Concurrent)
qt_standard_project_setup()

add_library(nekopic_core STATIC src/core/imageio.cpp src/core/imageio.h
    src/core/adjustments.cpp src/core/adjustments.h
    src/core/mosaic.cpp src/core/mosaic.h)
target_include_directories(nekopic_core PUBLIC src src/core)
target_link_libraries(nekopic_core PUBLIC Qt6::Core Qt6::Gui)

add_library(nekopic_app STATIC src/app/documentcontroller.cpp src/app/documentcontroller.h
    src/app/documentcontroller_mosaic.cpp src/app/documentcontroller_geometry.cpp
    src/app/filterpreviews.cpp src/app/filterpreviews.h)
target_include_directories(nekopic_app PUBLIC src)
target_link_libraries(nekopic_app PUBLIC nekopic_core Qt6::Concurrent Qt6::Quick)

qt_add_executable(nekopic src/app/main.cpp)
target_sources(nekopic PRIVATE src/app/languagemanager.cpp src/app/languagemanager.h)
target_link_libraries(nekopic PRIVATE nekopic_app Qt6::Quick Qt6::Qml Qt6::QuickControls2)
file(GLOB_RECURSE NEKOPIC_QML CONFIGURE_DEPENDS RELATIVE "${CMAKE_CURRENT_SOURCE_DIR}" "qml/*.qml")
list(FILTER NEKOPIC_QML EXCLUDE REGEX "^qml/tests/")
qt_add_resources(nekopic qml_resources PREFIX "/" FILES ${NEKOPIC_QML})
find_program(QT_LRELEASE NAMES lrelease HINTS "${QT6_INSTALL_PREFIX}/lib/qt6/bin" /usr/lib/qt6/bin REQUIRED)
set(NEKOPIC_QM "${CMAKE_CURRENT_BINARY_DIR}/nekopic_zh_CN.qm")
add_custom_command(OUTPUT "${NEKOPIC_QM}"
    COMMAND "${QT_LRELEASE}" "${CMAKE_CURRENT_SOURCE_DIR}/i18n/nekopic_zh_CN.ts" -qm "${NEKOPIC_QM}"
    DEPENDS i18n/nekopic_zh_CN.ts VERBATIM)
set_source_files_properties("${NEKOPIC_QM}" PROPERTIES QT_RESOURCE_ALIAS "nekopic_zh_CN.qm")
qt_add_resources(nekopic translations PREFIX "/i18n" FILES "${NEKOPIC_QM}")

foreach(target nekopic_core nekopic_app nekopic)
    target_compile_options(${target} PRIVATE -Wall -Wextra -Wpedantic)
endforeach()

include(CTest)
if(BUILD_TESTING)
    find_package(Qt6 6.5 REQUIRED COMPONENTS Test)
    add_executable(imageio_test tests/tst_imageio.cpp)
    target_link_libraries(imageio_test PRIVATE nekopic_core Qt6::Test)
    add_test(NAME imageio COMMAND imageio_test)
    add_executable(adjustments_test tests/tst_adjustments.cpp)
    target_link_libraries(adjustments_test PRIVATE nekopic_core Qt6::Test)
    add_test(NAME adjustments COMMAND adjustments_test)
    add_executable(mosaic_test tests/tst_mosaic.cpp)
    target_link_libraries(mosaic_test PRIVATE nekopic_core Qt6::Test)
    add_test(NAME mosaic COMMAND mosaic_test)
    add_executable(documentcontroller_test tests/documentcontroller_test.cpp)
    target_link_libraries(documentcontroller_test PRIVATE nekopic_app Qt6::Test)
    add_test(NAME documentcontroller COMMAND documentcontroller_test)
    add_executable(crop_test tests/tst_crop.cpp)
    target_link_libraries(crop_test PRIVATE nekopic_app Qt6::Test)
    add_test(NAME crop COMMAND crop_test)
    add_executable(filterpreviews_test tests/tst_filterpreviews.cpp)
    target_link_libraries(filterpreviews_test PRIVATE nekopic_app Qt6::Test)
    add_test(NAME filterpreviews COMMAND filterpreviews_test)
    set_tests_properties(imageio documentcontroller crop filterpreviews PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
endif()
