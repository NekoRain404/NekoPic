# NekoPic packaging

Distribution metadata for the native Qt 6 application. These files are consumed
by the install rules in `native/CMakeLists.txt`; they are not used by the H5
prototype at the repository root.

| File | Purpose |
| --- | --- |
| `nekopic.desktop` | Desktop Entry (`Exec=nekopic %f`, MIME associations) |
| `nekopic.metainfo.xml` | AppStream 1.0 component metadata |
| `nekopic.svg` | Scalable application icon (hicolor scalable/apps) |
| `flatpak/io.github.nekopic.NekoPic.yml` | Experimental Flatpak manifest |

## Build, install and package

From the repository root:

```sh
# Staged install into a temporary root (does not touch /usr)
cmake -S native -B native/build-release -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build native/build-release -j"$(nproc)"
ctest --test-dir native/build-release --output-on-failure
DESTDIR=/tmp/nekopic-root cmake --install native/build-release --prefix /usr
find /tmp/nekopic-root -type f | sort

# Real install (requires write access to /usr)
sudo cmake --install native/build-release --prefix /usr

# One-shot release build that runs ctest and CPack
./scripts/package.sh
```

`scripts/package.sh` configures a fresh Release build (using `cmake --fresh` when
available), runs CTest, then writes `<build-dir>/packages/*.tar.gz` and
`*.deb`. Use `--no-tests`, `--generators "TGZ"`, or `--build-dir DIR` to change
the behaviour.

CPack can also be run directly on a configured build:

```sh
cpack --config native/build-release/CPackConfig.cmake -G "TGZ;DEB" \
      -B native/build-release/packages
```

The install tree is:

```text
/usr/bin/nekopic
/usr/share/applications/nekopic.desktop
/usr/share/metainfo/nekopic.metainfo.xml
/usr/share/icons/hicolor/scalable/apps/nekopic.svg
/usr/share/doc/nekopic/README.md
/usr/share/doc/nekopic/packaging.md
```

No host-specific install RPATH is set: NekoPic links Qt and its own static
libraries, and the binary lives in the normal system path. Qt may add a
relocatable `$ORIGIN:$ORIGIN/../lib` RUNPATH during install; never replace it
with a build-machine path.

## Validation

```sh
desktop-file-validate packaging/nekopic.desktop
appstreamcli validate --no-net packaging/nekopic.metainfo.xml

# Validate the staged copies exactly as installed
desktop-file-validate /tmp/nekopic-root/usr/share/applications/nekopic.desktop
appstreamcli validate --no-net \
    /tmp/nekopic-root/usr/share/metainfo/nekopic.metainfo.xml

# Inspect the Debian metadata without installing
dpkg-deb -I native/build-package/packages/nekopic_0.1.0_amd64.deb
dpkg-deb -c native/build-package/packages/nekopic_0.1.0_amd64.deb
```

## Flatpak (experimental)

`packaging/flatpak/io.github.nekopic.NekoPic.yml` targets `org.kde.Platform` /
`org.kde.Sdk` 6.8 and requests image directories only (no network). It has not
been built against a real runtime; verify before advertising support:

```sh
flatpak install flathub org.kde.Platform//6.8 org.kde.Sdk//6.8
flatpak-builder --user --install --force-clean \
    packaging/flatpak/build packaging/flatpak/io.github.nekopic.NekoPic.yml
flatpak run io.github.nekopic.NekoPic
```

## AppImage

There is no AppImage recipe yet. When adding one, bundle the Qt Quick QML
modules and platform plugins (for example with `linuxdeploy` plus its Qt
plugin), validate the result on a clean distribution, and keep the AppImage
outside the source tree. Do not publish an untested AppImage.

## License TODO

The repository currently has no `LICENSE` file. The AppStream file uses
`LicenseRef-proprietary` only as a placeholder; it is **not** a chosen project
license. The owner must pick a license, add `LICENSE`, update both
`metadata_license` and `project_license` with valid SPDX identifiers, and then
re-check the obligations of Qt, image codecs, bundled fonts, and sample assets.
Until that happens, do not publish packages or submit to Flathub.

Screenshots are also a TODO: AppStream requires stable HTTPS URLs, not paths
inside this repository. See the commented template in `nekopic.metainfo.xml`.
Until a real project website exists, `appstreamcli validate` also reports
`url-homepage-missing`; do not replace it with a placeholder URL.
