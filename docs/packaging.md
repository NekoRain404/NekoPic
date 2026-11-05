# 打包与发布

本文描述原生 NekoPic（`native/`）的 Linux 安装、CPack 打包、元数据校验和
发布检查清单。H5 原型不参与打包。

当前状态：

- `native/CMakeLists.txt` 已包含 GNUInstallDirs 安装规则；
- CPack 生成 TGZ 与 DEB，配置位于 `native/cmake/NekoPicPackaging.cmake`；
- 桌面入口、AppStream 元数据和 SVG 图标位于 `packaging/`；
- Flatpak manifest 为实验性，尚未在真实运行时中验证；
- AppImage 尚未提供配方；
- 项目尚未选择许可证，发布前必须解决。

## 依赖

构建需要：

- CMake 3.21+、Ninja（推荐）、支持 C++20 的编译器；
- Qt 6.5+ 的 Core、Gui、Qml、Quick、QuickControls2、Concurrent；
- 生成翻译需要 Qt Linguist 的 `lrelease`；
- 构建测试需要 Qt Test，QML 测试需要 `qmltestrunner`；
- 有 shader 源文件时需要 Qt ShaderTools（`qsb`）。

打包和校验额外需要：

- CPack（随 CMake 提供）、`dpkg-deb`（生成 DEB）；
- 可选：`desktop-file-validate`（desktop-file-utils）、`appstreamcli`
  （AppStream）、`flatpak-builder`。

本仓库在 Qt 6.12.0 / CMake 4.4.5 / GCC 16.2.1 上验证过构建。最低 Qt 6.5
和最低 CMake 3.21 仍需在目标发行版重新验证。

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
`stable` 或移除该属性。

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

### CPack

```sh
# 推荐：干净 Release 构建 + ctest + cpack
./scripts/package.sh

# 指定构建目录 / 跳过测试 / 只生成 TGZ
./scripts/package.sh --build-dir /tmp/nekopic-package --no-tests
./scripts/package.sh --generators "TGZ"

# 对已有构建直接运行 CPack
cpack --config native/build-release/CPackConfig.cmake -G "TGZ;DEB" \
      -B native/build-release/packages
```

产物位置：`native/build-package/packages/`（默认）或脚本输出的绝对路径。
DEB 文件名遵循 `DEB-DEFAULT`：`nekopic_<version>_<arch>.deb`。

### 元数据校验

```sh
desktop-file-validate packaging/nekopic.desktop
appstreamcli validate --no-net packaging/nekopic.metainfo.xml

desktop-file-validate \
    /tmp/nekopic-root/usr/share/applications/nekopic.desktop
appstreamcli validate --no-net \
    /tmp/nekopic-root/usr/share/metainfo/nekopic.metainfo.xml

# 查看 DEB 控制信息和文件列表，不安装
dpkg-deb -I native/build-package/packages/nekopic_0.1.0_amd64.deb
dpkg-deb -c native/build-package/packages/nekopic_0.1.0_amd64.deb
```

校验失败必须记录并修复，不能因为“文件已安装”而忽略。当前仓库没有许可证和
项目主页，`appstreamcli validate` 会报告 `metadata-license-invalid`
（`LicenseRef-proprietary` 占位）与 `url-homepage-missing`；这两项属于未解决
的发布 TODO，不能通过伪造许可证或 URL 消除。`cid-contains-uppercase-letter`
是 pedantic 提示，当前 id 与 Flatpak app id 一致，保留 PascalCase。

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

## 安装树

GNUInstallDirs 变量决定路径，默认前缀为 `/usr`：

```text
${CMAKE_INSTALL_BINDIR}/nekopic
${CMAKE_INSTALL_DATADIR}/applications/nekopic.desktop
${CMAKE_INSTALL_DATADIR}/metainfo/nekopic.metainfo.xml
${CMAKE_INSTALL_DATADIR}/icons/hicolor/scalable/apps/nekopic.svg
${CMAKE_INSTALL_DATADIR}/doc/nekopic/README.md
${CMAKE_INSTALL_DATADIR}/doc/nekopic/packaging.md
```

若仓库以后出现 `LICENSE`，安装规则会自动把它复制到文档目录。二进制使用
静态内部库和系统 Qt，不需要指向构建机的 RPATH；Qt 6 会在安装时加入可重定位
的 `$ORIGIN:$ORIGIN/../lib`，不要把它改成绝对主机路径。

## 发布检查清单

1. `git status --short --branch` 干净，位于预期分支。
2. 版本号、AppStream release 和 git tag 一致。
3. Release 构建与 CTest 全部通过；必要时加跑 QML 测试。
4. `cmake --install` 到 `DESTDIR`，逐项检查安装树和文件权限。
5. `desktop-file-validate` 和 `appstreamcli validate --no-net` 通过；记录
   无法消除的 warning。
6. DEB 的 `Depends` 在目标发行版上可解析；依赖包名按 §依赖说明复核。
7. 在干净环境实机启动安装后的 `nekopic`，打开、编辑、保存一张图片。
8. 检查许可证：仓库内 `LICENSE` 存在，AppStream 使用真实 SPDX 标识符，
   第三方库、字体、示例图片和编解码器义务已核对。
9. 提供真实 HTTPS 截图并取消 AppStream 中的 TODO 注释。
10. 生成 SHA-256 校验和，例如：
    `sha256sum native/build-package/packages/nekopic_* > SHA256SUMS`。
11. 只提交源文件和元数据；构建目录与包产物保持在 Git 之外。

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
（QML 模块仍需手工声明）。Flatpak 由 `org.kde.Platform` 提供 Qt 与 QML
模块，不需要这些依赖。

图片读写格式取决于部署环境中的 Qt 图像插件；界面只展示实际可用的导出
格式。打包不得承诺未验证的 WebP、AVIF、JPEG XL、HEIF/RAW 等支持，应在
发布说明中列出实测矩阵。

## 许可证 TODO

仓库目前没有 `LICENSE` 文件。`packaging/nekopic.metainfo.xml` 使用
`LicenseRef-proprietary` 只是占位符，表示“尚未选择许可证”，不是实际授权。

发布前必须由项目所有者：

1. 选择项目许可证并加入 `LICENSE`；
2. 将 `metadata_license` 和 `project_license` 改为有效 SPDX 表达式；
3. 核对 Qt（LGPL/GPL 或商业授权）、图像编解码器插件、字体、滤镜/示例图片
   的分发条件；
4. 如采用 Copyleft，确认静态链接的 `nekopic_*` 库与最终链接方式符合义务。

在这些事项完成前，不应发布二进制包或提交 Flathub。

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
- **QML 模块运行时缺失**：安装上文列出的 `qml6-module-*` 包；只在构建机
  测试过、未安装运行时模块的 DEB 会在启动时报 import 错误。
- **DEB 依赖无法安装**：先核对目标发行版的 Qt 包名，必要时临时把
  `CPACK_DEBIAN_PACKAGE_SHLIBDEPS` 设为 `ON` 并补充 QML 模块依赖。
- **AppStream 校验报告许可证**：这是预期的 TODO，不能通过伪造许可证消除。

## 相关文件

- `native/CMakeLists.txt`：安装规则；
- `native/cmake/NekoPicPackaging.cmake`：CPack 配置；
- `scripts/package.sh`：一键 Release 打包；
- `packaging/README.md`：打包目录速查；
- `packaging/nekopic.desktop`、`packaging/nekopic.metainfo.xml`、
  `packaging/nekopic.svg`、`packaging/flatpak/`。
