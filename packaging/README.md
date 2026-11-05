# NekoPic packaging

Distribution metadata for the native Qt 6 application. These files are consumed
by the install rules in `native/CMakeLists.txt`; they are not used by the H5
prototype at the repository root.

| File | Purpose |
| --- | --- |
| `nekopic.desktop` | Desktop Entry (`Exec=nekopic %f`, MIME associations) |
| `nekopic.metainfo.xml` | AppStream 1.0 component metadata |
| `nekopic.svg` | Scalable application icon (hicolor scalable/apps) |
| `icons/hicolor/<size>x<size>/apps/nekopic.png` | 16–512 px hicolor icons |
| `appimage/AppRun` | AppDir entry point used by `scripts/build-appimage.sh` |
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

# One-shot release build: ctest + TGZ/DEB/RPM where the tools exist + SHA256SUMS
./scripts/package.sh
```

`scripts/package.sh` configures a fresh Release build (using `cmake --fresh` when
available), runs CTest, then writes packages plus `SHA256SUMS` to
`<build-dir>/packages`. Missing `dpkg-deb` or `rpmbuild` is reported and the
corresponding generator is skipped. Use `--no-tests`, `--generators "TGZ;RPM"`,
or `--build-dir DIR` to change the behaviour.

CPack can also be run directly on a configured build:

```sh
cpack --config native/build-release/CPackConfig.cmake -G "TGZ;DEB;RPM" \
      -B native/build-release/packages
```

The install tree is:

```text
/usr/bin/nekopic
/usr/share/applications/nekopic.desktop
/usr/share/metainfo/nekopic.metainfo.xml
/usr/share/icons/hicolor/scalable/apps/nekopic.svg
/usr/share/icons/hicolor/<size>x<size>/apps/nekopic.png
/usr/share/doc/nekopic/README.md
/usr/share/doc/nekopic/packaging.md
```

`<size>` is 16, 24, 32, 48, 64, 128, 256 and 512. Regenerate the PNGs with
`./scripts/generate-icons.sh` after changing the SVG.

No host-specific install RPATH is set: NekoPic links Qt and its own static
libraries, and the binary lives in the normal system path. Qt may add a
relocatable `$ORIGIN:$ORIGIN/../lib` RUNPATH during install; never replace it
with a build-machine path.

## AppImage

`scripts/build-appimage.sh` builds a single-file AppImage. It needs
`linuxdeploy` and `linuxdeploy-plugin-qt` (Qt 6); `appimagetool` is optional.
The script installs into an AppDir, copies the desktop file/icon/AppRun, deploys
Qt libraries and QML modules, then writes one `.AppImage` plus `SHA256SUMS`.

```sh
./scripts/build-appimage.sh
./scripts/build-appimage.sh --build-dir /tmp/nekopic-appimage \
    --output-dir /tmp/nekopic-artifacts
./scripts/build-appimage.sh --stage-only   # no AppImage tools required
```

If the tools are missing, the script keeps and validates the staged AppDir,
prints upstream install links and exits non-zero without producing a fake
AppImage. The AppRun template is `packaging/appimage/AppRun`.

## Validation

```sh
desktop-file-validate packaging/nekopic.desktop
appstreamcli validate --no-net packaging/nekopic.metainfo.xml

# Validate the staged copies exactly as installed
desktop-file-validate /tmp/nekopic-root/usr/share/applications/nekopic.desktop
appstreamcli validate --no-net \
    /tmp/nekopic-root/usr/share/metainfo/nekopic.metainfo.xml

# Debian metadata and file list
dpkg-deb -I native/build-package/packages/nekopic_0.1.0_amd64.deb
dpkg-deb -c native/build-package/packages/nekopic_0.1.0_amd64.deb

# RPM metadata and file list without touching the system rpmdb
mkdir -p /tmp/nekopic-rpmdb
rpm --dbpath /tmp/nekopic-rpmdb -qip \
    native/build-package/packages/nekopic-0.1.0-1.x86_64.rpm
rpm --dbpath /tmp/nekopic-rpmdb -qp --requires \
    native/build-package/packages/nekopic-0.1.0-1.x86_64.rpm
rpm --dbpath /tmp/nekopic-rpmdb -qlp \
    native/build-package/packages/nekopic-0.1.0-1.x86_64.rpm

# Checksums for every CPack artifact
cd native/build-package/packages && sha256sum -c SHA256SUMS
```

AppStream currently reports `metadata-license-invalid` for the
`LicenseRef-proprietary` placeholder and `url-homepage-missing`; both are
documented release TODOs. No screenshot URLs exist yet, so no fake URLs were
added.

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

## License TODO

The repository currently has no `LICENSE` file. AppStream and the RPM metadata
use `LicenseRef-proprietary` only as a placeholder; it is **not** a chosen
project license. The owner must pick a license, add `LICENSE`, update
`metadata_license`, `project_license` and `CPACK_RPM_PACKAGE_LICENSE` with valid
SPDX identifiers, and then re-check the obligations of Qt, image codecs,
bundled fonts, and sample assets. Until that happens, do not publish packages,
an AppImage or a Flathub submission.

Screenshots are also a TODO: AppStream requires stable HTTPS URLs, not paths
inside this repository. See the commented template in `nekopic.metainfo.xml`.
Until a real project website exists, `appstreamcli validate` also reports
`url-homepage-missing`; do not replace it with a placeholder URL.
