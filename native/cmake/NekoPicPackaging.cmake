# CPack configuration for Linux binary packages.
#
# Included last from native/CMakeLists.txt. The install tree itself is defined
# by the install() rules in that file; this module only describes the packages.
# Build artifacts are written to the caller-chosen CPack output directory, e.g.
#   cpack --config native/build-release/CPackConfig.cmake -G "TGZ;DEB;RPM"
# or through scripts/package.sh.

if(NOT UNIX OR APPLE)
    return()
endif()

set(CPACK_PACKAGE_NAME "nekopic")
set(CPACK_PACKAGE_VENDOR "NekoPic contributors")
set(CPACK_PACKAGE_VERSION "${PROJECT_VERSION}")
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "Simple photo editor for the Linux desktop")
set(CPACK_PACKAGE_DESCRIPTION
"NekoPic is a Qt Quick photo editor for the Linux desktop. It opens images
through Qt's image plugins, applies non-destructive adjustments, filters,
crop, drawing and text objects, and exports the merged result.")
# TODO(owner): replace the reserved .invalid address once a real project
# contact exists. CPack and dpkg require a maintainer field.
set(CPACK_PACKAGE_CONTACT "NekoPic contributors <maintainers@nekopic.invalid>")

# Install layout for archives and packages, independent of the build-time
# CMAKE_INSTALL_PREFIX (which may be a local staging directory).
set(CPACK_PACKAGING_INSTALL_PREFIX "/usr")

set(CPACK_GENERATOR "TGZ;DEB;RPM")
set(CPACK_SOURCE_GENERATOR "TGZ")
set(CPACK_SOURCE_IGNORE_FILES
    "/build[^/]*/"
    "/\\.git/"
    "/\\.claude/"
    "/artifacts/"
    "/packaging/flatpak/build/"
    "~$")

set(CPACK_DEBIAN_PACKAGE_NAME "nekopic")
set(CPACK_DEBIAN_PACKAGE_SECTION "graphics")
set(CPACK_DEBIAN_PACKAGE_PRIORITY "optional")
set(CPACK_DEBIAN_PACKAGE_MAINTAINER "NekoPic contributors")
set(CPACK_DEBIAN_FILE_NAME "DEB-DEFAULT")
set(CPACK_DEBIAN_COMPRESSION_TYPE "xz")
# Dependencies are declared explicitly so packaging does not depend on the
# build host's shared-library layout. dpkg-shlibdeps remains an alternative
# (set CPACK_DEBIAN_PACKAGE_SHLIBDEPS ON) when packaging on the target distro.
set(CPACK_DEBIAN_PACKAGE_SHLIBDEPS OFF)
string(CONCAT CPACK_DEBIAN_PACKAGE_DEPENDS
    "libqt6core6 (>= 6.5.0), libqt6gui6 (>= 6.5.0), libqt6qml6 (>= 6.5.0), "
    "libqt6quick6 (>= 6.5.0), libqt6quickcontrols2-6 (>= 6.5.0), "
    "libqt6concurrent6 (>= 6.5.0), "
    "qml6-module-qtcore, qml6-module-qtqml, qml6-module-qtqml-models, "
    "qml6-module-qtqml-workerscript, qml6-module-qtquick, "
    "qml6-module-qtquick-controls, qml6-module-qtquick-dialogs, "
    "qml6-module-qtquick-layouts, qml6-module-qtquick-templates, "
    "qml6-module-qtquick-window")

# --- RPM -----------------------------------------------------------------
# Dependency names follow the Fedora/qt6-qt* family. Other RPM distributions
# (for example openSUSE's libQt6Core6 scheme) need these names adjusted, or
# CPACK_RPM_PACKAGE_AUTOREQ left ON to derive shared-library dependencies.
set(CPACK_RPM_PACKAGE_NAME "nekopic")
set(CPACK_RPM_PACKAGE_SUMMARY "Simple photo editor for the Linux desktop")
set(CPACK_RPM_PACKAGE_DESCRIPTION "${CPACK_PACKAGE_DESCRIPTION}")
string(CONCAT CPACK_RPM_PACKAGE_REQUIRES
    "qt6-qtbase >= 6.5, qt6-qtdeclarative >= 6.5, "
    "qt6-qtquickcontrols2, qt6-qtwayland")
# TODO(owner): placeholder only; see docs/packaging.md. A real license must be
# chosen and this field updated before publishing.
set(CPACK_RPM_PACKAGE_LICENSE "LicenseRef-proprietary")
set(CPACK_RPM_PACKAGE_GROUP "Applications/Multimedia")
set(CPACK_RPM_PACKAGE_RELEASE "1")
set(CPACK_RPM_FILE_NAME "RPM-DEFAULT")
# Explicit Requires above keep the package deterministic; rpmbuild's automatic
# ELF dependency scan would otherwise depend on the packaging host.
set(CPACK_RPM_PACKAGE_AUTOREQ OFF)
set(CPACK_RPM_PACKAGE_AUTOPROV OFF)

set(CPACK_STRIP_FILES TRUE)
set(CPACK_VERBATIM_VARIABLES TRUE)

include(CPack)
