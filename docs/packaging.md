# 打包与发布

本文描述原生 NekoPic（`native/`）的 Linux 安装、CPack、AppImage、元数据校验
和发布检查清单。H5 原型不参与打包。

当前状态：

- `native/CMakeLists.txt` 已包含 GNUInstallDirs 安装规则；
- CPack 生成 TGZ、DEB 与 RPM，配置位于
  `native/cmake/NekoPicPackaging.cmake`；
- 桌面入口、AppStream 元数据、SVG 与 16–512 px hicolor PNG 图标位于
  `packaging/`；
- `scripts/build-appimage.sh` 可生成单文件 AppImage；本机已用 linuxdeploy 与
  appimagetool 实际产出 `NekoPic-0.1.0-x86_64.AppImage`；
- AppImage 默认设置 `NO_STRIP=1`（旧 binutils 无法读取新式 `.relr.dyn`）和
  `APPIMAGE_EXTRACT_AND_RUN=1`（无 FUSE 时可运行）；
- Flatpak manifest 为实验性，尚未在真实运行时中验证；
- 项目尚未选择许可证，发布前必须解决。

## 依赖

构建需要：

- CMake 3.21+、Ninja（推荐）、支持 C++20 的编译器；
- Qt 6.5+ 的 Core、Gui、Qml、Quick、QuickControls2、Concurrent；
- 生成翻译需要 Qt Linguist 的 `lrelease`；
- 构建测试需要 Qt Test，QML 测试需要 `qmltestrunner`；
- 有 shader 源文件时需要 Qt ShaderTools（`qsb`）。

打包和校验额外需要：

- CPack（随 CMake 提供）；
- DEB：`dpkg-deb`；
- RPM：`rpmbuild` / `rpm`（Fedora、RHEL、openSUSE 等）；
- AppImage：`linuxdeploy`、`linuxdeploy-plugin-qt`（Qt 6），可选
  `appimagetool`；
- 图标再生成：`rsvg-convert`（librsvg）或 ImageMagick；
- 校验：`desktop-file-validate`（desktop-file-utils）、`appstreamcli`
  （AppStream），可选 `identify`（ImageMagick）与 `flatpak-builder`。

AppImage 工具不在仓库中，也不在标准发行版仓库里。请从上游下载可执行文件并
加入 `PATH`：

```text
https://github.com/linuxdeploy/linuxdeploy/releases
https://github.com/linuxdeploy/linuxdeploy-plugin-qt/releases
https://github.com/AppImage/appimagetool/releases
```

本仓库在 Qt 6.12.0 / CMake 4.4.5 / GCC 16.2.1 / rpm 6.0.1 上验证过构建和
RPM 生成。最低 Qt 6.5、最低 CMake 3.21 仍需在目标发行版重新验证。

## 版本管理

`native/CMakeLists.txt` 的 `project(NekoPic VERSION 0.1.0 ...)` 是唯一版本
来源：它生成 `NEKOPIC_VERSION`，`--version` 和设置页都读取该值。发布时：

1. 修改 `project(... VERSION x.y.z ...)`；
2. 在 `packaging/nekopic.metainfo.xml` 增加同版本的 `<release>`，填写真实
   日期和变更摘要；
3. 0.x 阶段遵循语义化版本：新功能升 minor，修复升 patch，破坏性变更在
   1.0 前也升 minor；
4. 提交后打 annotated tag：`git tag -a vX.Y.Z -m "NekoPic X.Y.Z"`；
5. 不要把构建目录、包产物或安装暂存目录提交进 Git。

AppStream release 的 `type="development"` 表示预发布；稳定版本发布时改为
`stable` 或移除该属性。RPM 的 `Release` 字段由 CPack 固定为 `1`；同一版本
重新打包发行版修订时，应显式调整该字段并重新生成校验和。

## 常用命令

以下命令从仓库根目录运行。

### 构建、测试、暂存安装

```sh
cmake -S native -B native/build-release -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build native/build-release -j"$(nproc)"
ctest --test-dir native/build-release --output-on-failure

# QML 测试（可选，需 qmltestrunner）
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner \
    -input native/qml/tests -silent

# 安装到临时 root，不修改系统
rm -rf /tmp/nekopic-root
DESTDIR=/tmp/nekopic-root cmake --install native/build-release --prefix /usr
find /tmp/nekopic-root -type f | sort

# 实际安装
sudo cmake --install native/build-release --prefix /usr
```

`cmake --install` 会在构建目录写入 `install_manifest.txt`；卸载时可按该文件
逐项删除，或由发行版包管理器负责。

### CPack：TGZ / DEB / RPM

```sh
# 推荐：干净 Release 构建 + ctest + 全部可用 CPack 生成器
./scripts/package.sh

# 指定构建目录 / 跳过测试 / 只生成部分包
./scripts/package.sh --build-dir /tmp/nekopic-package --no-tests
./scripts/package.sh --generators "TGZ;DEB"
./scripts/package.sh --generators "RPM"

# 对已有构建直接运行 CPack
cpack --config native/build-release/CPackConfig.cmake -G "TGZ;DEB;RPM" \
      -B native/build-release/packages
```

`package.sh` 会检测 `dpkg-deb` 与 `rpmbuild`：缺失的生成器会被跳过并打印
原因，不会产生伪造的包。产物位置：`native/build-package/packages/`（默认）
或脚本输出的绝对路径：

```text
nekopic-0.1.0-Linux.tar.gz
nekopic_0.1.0_amd64.deb
nekopic-0.1.0-1.x86_64.rpm
SHA256SUMS
```

DEB 文件名遵循 `DEB-DEFAULT`，RPM 遵循 `RPM-DEFAULT`。脚本最后运行
`sha256sum` 并写入 `SHA256SUMS`；验证：

```sh
cd native/build-package/packages
sha256sum -c SHA256SUMS
```

### AppImage

```sh
# 完整流程：Release 构建 + AppDir + linuxdeploy + 单个 .AppImage
./scripts/build-appimage.sh

# 指定构建/输出目录，复用已有构建
./scripts/build-appimage.sh --build-dir /tmp/nekopic-appimage \
    --output-dir /tmp/nekopic-artifacts
./scripts/build-appimage.sh --build-dir native/build-package --no-build

# 只暂存并校验 AppDir，不需要 AppImage 工具
./scripts/build-appimage.sh --stage-only
```

输出文件名为 `NekoPic-<version>-<arch>.AppImage`，并在同目录写入
`SHA256SUMS`。脚本会：

1. 把应用安装到 `<build-dir>/AppDir/usr`；
2. 复制根目录 desktop 文件、512 px PNG、`.DirIcon`、SVG 和 AppRun 模板；
3. 调用 `desktop-file-validate`、检查 16–512 px hicolor 图标和 AppRun；
4. 用 linuxdeploy 与 Qt 插件收集 Qt 库、平台插件和 QML 模块；
5. 优先用 `appimagetool` 打包，否则回退到
   `linuxdeploy --output appimage`；
6. 确认输出目录只有一个 `.AppImage`，再生成校验和。

如果缺少 linuxdeploy / linuxdeploy-plugin-qt，脚本会保留并校验 AppDir、打印
安装说明，然后以非零状态退出；不会生成不可用的假 AppImage。

本机实测产物（2026-11-05）：

```text
artifacts/appimage/NekoPic-0.1.0-x86_64.AppImage   76 MB
sha256  489e601cb4277ed9d9193e8186aef78717c09dee2ac8461800647e1946caca4a
```

AppImage 的 `AppRun` 默认在存在 `DISPLAY` 时使用 xcb（XWayland），以避免部分
Qt 6.12 Wayland 客户端在 bundled 依赖下不提交首帧；需要原生 Wayland 时设置
`NEKOPIC_APPIMAGE_PLATFORM=wayland`。包内仍包含 wayland/xcb/offscreen 平台插件和
QML 模块。
AppImage 的
`AppRun` 模板位于 `packaging/appimage/AppRun`，负责设置 `LD_LIBRARY_PATH`、
`QT_PLUGIN_PATH`、`QML2_IMPORT_PATH` 等路径。

### 图标集

`packaging/icons/hicolor/` 保存从 `packaging/nekopic.svg` 生成的
16/24/32/48/64/128/256/512 px PNG。重新生成：

```sh
./scripts/generate-icons.sh
```

需要 `rsvg-convert` 或 ImageMagick。PNG 已提交，发布构建不依赖 SVG 光栅化
工具。CMake 会把全部尺寸和 scalable SVG 安装到 hicolor 目录；DEB/RPM 和
AppDir 复用同一套文件。

### Flatpak（实验性）

```sh
flatpak install flathub org.kde.Platform//6.8 org.kde.Sdk//6.8
flatpak-builder --user --install --force-clean \
    packaging/flatpak/build packaging/flatpak/io.github.nekopic.NekoPic.yml
flatpak run io.github.nekopic.NekoPic
```

manifest 使用 `org.kde.Sdk` 6.8 和 CMake 构建，权限只包含显示、GPU 和常用
图片目录，不申请网络。尚未在真实 Flatpak 环境验证；在验证前不要对外宣称
支持 Flatpak。构建产物目录 `packaging/flatpak/build/` 不应提交。

## 校验

### 桌面入口与 AppStream

```sh
desktop-file-validate packaging/nekopic.desktop
appstreamcli validate --no-net packaging/nekopic.metainfo.xml

desktop-file-validate \
    /tmp/nekopic-root/usr/share/applications/nekopic.desktop
appstreamcli validate --no-net \
    /tmp/nekopic-root/usr/share/metainfo/nekopic.metainfo.xml
```

当前仓库没有许可证和项目主页，`appstreamcli validate` 会报告
`metadata-license-invalid`（`LicenseRef-proprietary` 占位）与
`url-homepage-missing`；这两项是未解决的发布 TODO，不能通过伪造许可证或
URL 消除。`cid-contains-uppercase-letter` 是 pedantic 提示，当前 id 与
Flatpak app id 一致，保留 PascalCase。截图目前只有注释模板，因此不存在
可检查的截图 URL；补图后应重新运行校验。

### DEB

```sh
dpkg-deb -I native/build-package/packages/nekopic_0.1.0_amd64.deb
dpkg-deb -c native/build-package/packages/nekopic_0.1.0_amd64.deb
dpkg-deb -f native/build-package/packages/nekopic_0.1.0_amd64.deb \
    Package Version Depends Section
```

### RPM

普通用户查询本地 RPM 时，`rpm` 可能尝试写 `/var/lib/rpm`。使用临时 dbpath
可以避免权限问题：

```sh
mkdir -p /tmp/nekopic-rpmdb
rpm --dbpath /tmp/nekopic-rpmdb -qip \
    native/build-package/packages/nekopic-0.1.0-1.x86_64.rpm
rpm --dbpath /tmp/nekopic-rpmdb -qp --requires \
    native/build-package/packages/nekopic-0.1.0-1.x86_64.rpm
rpm --dbpath /tmp/nekopic-rpmdb -qp --license \
    native/build-package/packages/nekopic-0.1.0-1.x86_64.rpm
rpm --dbpath /tmp/nekopic-rpmdb -qlp \
    native/build-package/packages/nekopic-0.1.0-1.x86_64.rpm
```

检查 `Name`、`Version`、`Release`、`License`、`Group`、`Requires` 和文件列表
是否包含 `nekopic.desktop`、`nekopic.metainfo.xml` 以及全部图标尺寸。

### AppImage

即使没有 linuxdeploy，也可以用 `--stage-only` 检查桌面文件与图标：

```sh
./scripts/build-appimage.sh --stage-only
desktop-file-validate native/build-appimage/AppDir/nekopic.desktop
find native/build-appimage/AppDir/usr/share/icons/hicolor -name nekopic.png
identify native/build-appimage/AppDir/nekopic.png \
    native/build-appimage/AppDir/.DirIcon
test -x native/build-appimage/AppDir/AppRun
```

成功生成 AppImage 后：

```sh
file native/build-appimage/packages/NekoPic-0.1.0-x86_64.AppImage
cd native/build-appimage/packages && sha256sum -c SHA256SUMS
```

可选实机验证：在干净桌面运行 AppImage，检查窗口图标、文件对话框、打开/
保存和中文显示；也可用 `--appimage-extract` 检查 bundle 内容。

## 安装树

GNUInstallDirs 变量决定路径，默认前缀为 `/usr`：

```text
${CMAKE_INSTALL_BINDIR}/nekopic
${CMAKE_INSTALL_DATADIR}/applications/nekopic.desktop
${CMAKE_INSTALL_DATADIR}/metainfo/nekopic.metainfo.xml
${CMAKE_INSTALL_DATADIR}/icons/hicolor/scalable/apps/nekopic.svg
${CMAKE_INSTALL_DATADIR}/icons/hicolor/<size>x<size>/apps/nekopic.png
${CMAKE_INSTALL_DATADIR}/doc/nekopic/README.md
${CMAKE_INSTALL_DATADIR}/doc/nekopic/packaging.md
```

`<size>` 为 16、24、32、48、64、128、256、512。若仓库以后出现 `LICENSE`，
安装规则会自动把它复制到文档目录。二进制使用静态内部库和系统 Qt，不需要
指向构建机的 RPATH；Qt 6 会在安装时加入可重定位的
`$ORIGIN:$ORIGIN/../lib`，不要把它改成绝对主机路径。

## 发布检查清单

1. `git status --short --branch` 干净，位于预期分支。
2. 版本号、AppStream release 和 git tag 一致；RPM Release 已复核。
3. Release 构建与 CTest 全部通过；必要时加跑 QML 测试。
4. `cmake --install` 到 `DESTDIR`，逐项检查安装树、PNG/SVG 图标和权限。
5. `desktop-file-validate` 与 `appstreamcli validate --no-net` 通过；记录
   无法消除的 warning 与许可证 TODO。
6. DEB/RPM 的依赖在目标发行版上可解析；依赖包名按 §依赖说明复核。
7. RPM 在目标发行版用 `rpm -qip/-qlp` 检查，最好实际安装、卸载一次。
8. AppImage 在干净桌面启动，确认 Qt 平台插件、QML 模块和图标已打包。
9. 逐项检查 `SHA256SUMS`，并将校验和随发布说明一起发布。
10. 在干净环境实机启动安装后的 `nekopic`，打开、编辑、保存一张图片。
11. 检查许可证：仓库内 `LICENSE` 存在，AppStream 与 RPM 使用真实 SPDX
    标识符，第三方库、字体、示例图片和编解码器义务已核对。
12. 提供真实 HTTPS 截图并取消 AppStream 中的 TODO 注释。
13. 只提交源文件和元数据；构建目录与包产物保持在 Git 之外。

## 依赖说明

DEB 的 `Depends` 在 `native/cmake/NekoPicPackaging.cmake` 中显式列出：

- `libqt6core6`、`libqt6gui6`、`libqt6qml6`、`libqt6quick6`、
  `libqt6quickcontrols2-6`、`libqt6concurrent6`；
- Qt Quick 运行时 QML 模块：`qml6-module-qtcore`、`qml6-module-qtqml`、
  `qml6-module-qtqml-models`、`qml6-module-qtqml-workerscript`、
  `qml6-module-qtquick`、`qml6-module-qtquick-controls`、
  `qml6-module-qtquick-dialogs`、`qml6-module-qtquick-layouts`、
  `qml6-module-qtquick-templates`、`qml6-module-qtquick-window`。

这些名称按 Debian/Ubuntu 的 Qt 6 打包惯例编写，尚未在 Qt 6.12 的 Debian
目标上逐项验证。打包到其他发行版时，应使用该系统实际的包名，或改为
`CPACK_DEBIAN_PACKAGE_SHLIBDEPS ON` 让 `dpkg-shlibdeps` 推导共享库依赖
（QML 模块仍需手工声明）。

RPM 的 `Requires` 使用 Fedora/qt6-qt* 名称：

```text
qt6-qtbase >= 6.5
qt6-qtdeclarative >= 6.5
qt6-qtquickcontrols2
qt6-qtwayland
```

RPM 在 Arch 上生成了有效包并检查了元数据，但**没有在 Fedora/RHEL/openSUSE
上实际安装验证**。openSUSE 等使用 `libQt6Core6` 名称的发行版需要调整
`CPACK_RPM_PACKAGE_REQUIRES`，或改用
`CPACK_RPM_PACKAGE_AUTOREQ ON` 让 rpmbuild 推导共享库依赖。
`CPACK_RPM_PACKAGE_AUTOREQ` 当前为 `OFF`，以保证跨打包机结果稳定。

AppImage 会把 Qt 库、平台插件和 QML 模块打进单个文件，因此不依赖系统的
Qt 版本；代价是体积较大，且仍需目标系统满足 glibc/图形驱动基线。Flatpak
由 `org.kde.Platform` 提供 Qt 与 QML 模块，不需要上述包依赖。

图片读写格式取决于部署环境中的 Qt 图像插件；界面只展示实际可用的导出
格式。打包不得承诺未验证的 WebP、AVIF、JPEG XL、HEIF/RAW 等支持，应在
发布说明中列出实测矩阵。

## 许可证 TODO

仓库目前没有 `LICENSE` 文件。`packaging/nekopic.metainfo.xml` 和 RPM 的
`License` 字段使用 `LicenseRef-proprietary` 只是占位符，表示“尚未选择
许可证”，不是实际授权。

发布前必须由项目所有者：

1. 选择项目许可证并加入 `LICENSE`；
2. 将 `metadata_license`、`project_license` 和
   `CPACK_RPM_PACKAGE_LICENSE` 改为有效 SPDX 表达式；
3. 核对 Qt（LGPL/GPL 或商业授权）、图像编解码器插件、字体、滤镜/示例图片
   的分发条件；
4. 如采用 Copyleft，确认静态链接的 `nekopic_*` 库与最终链接方式符合义务。

在这些事项完成前，不应发布二进制包、AppImage 或提交 Flathub。

## AppStream 截图 TODO

AppStream 的 `<screenshot>` 只能使用 HTTPS URL，不能引用仓库内相对路径。
当前 `nekopic.metainfo.xml` 保留了注释模板；待有稳定的发布页或站点后：

1. 上传 16:9 或接近的 PNG 截图（至少一张默认图）；
2. 取消注释并替换示例 URL，补充准确的 caption；
3. 重新运行 `appstreamcli validate --no-net`。

不要使用 `example.invalid` 等假地址作为正式截图。

## 故障排查

- **找不到 `lrelease`**：CMake 会先查 `QT6_INSTALL_PREFIX/lib/qt6/bin`、
  `/usr/lib/qt6/bin`；其他布局请把 Qt Linguist 加入 `PATH`。
- **找不到 Qt ShaderTools**：`shaders/` 存在时构建会要求 `qsb`；安装
  Qt ShaderTools 或移除 shader 源后再构建。
- **QML 模块运行时缺失**：DEB 安装上文列出的 `qml6-module-*` 包；RPM 安装
  `qt6-qtdeclarative` 与 `qt6-qtquickcontrols2`；AppImage 应由 Qt 插件打包。
- **缺少 `rpmbuild`**：`package.sh` 会跳过 RPM 并打印提示；安装 `rpm-build`
  （Fedora）或 `rpm` 工具链后重跑。缺少 `dpkg-deb` 时同样跳过 DEB。
- **缺少 linuxdeploy**：AppImage 不会被生成；脚本会给出上游下载地址并保留
  已校验的 AppDir。只做暂存检查时加 `--stage-only`。
- **AppImage 启动时报 Qt 平台插件错误**：确认 `linuxdeploy-plugin-qt` 已被
  linuxdeploy 找到，并检查 AppRun 中的 `QT_PLUGIN_PATH` 与
  `QT_QPA_PLATFORM_PLUGIN_PATH`。
- **AppStream 校验报告许可证**：这是预期的 TODO，不能通过伪造许可证消除。

## 相关文件

- `native/CMakeLists.txt`：安装规则与图标安装；
- `native/cmake/NekoPicPackaging.cmake`：CPack TGZ/DEB/RPM 配置；
- `scripts/package.sh`：一键 Release 打包与校验和；
- `scripts/build-appimage.sh`：AppImage/AppDir 构建；
- `scripts/generate-icons.sh`：从 SVG 生成 hicolor PNG；
- `packaging/README.md`：打包目录速查；
- `packaging/nekopic.desktop`、`packaging/nekopic.metainfo.xml`、
  `packaging/nekopic.svg`、`packaging/icons/`、`packaging/appimage/`、
  `packaging/flatpak/`。

## 元数据快速校验

```sh
./scripts/validate-packaging.sh        # 开发模式：许可证/主页占位只告警
./scripts/validate-packaging.sh --strict  # 发布门禁
```

脚本检查 desktop、AppStream、SVG、16–512 px 图标、AppDir（若存在）和
LICENSE 缺失；CI 已接入开发模式。
