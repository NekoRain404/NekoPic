# 开发流程与版本管理

## 分支模型

- `master`：只保留已验证的基线；不直接开发。
- `develop`：集成分支，所有工作流合并到这里，必须保持构建与测试通过。
- `feature/<topic>`：单一能力；从 `develop` 切出，完成后合并回 `develop`。
- `spike/<topic>`：调研/基准；可以只提交文档与实验结论，合入前决定是否保留代码。

当前基线：

```text
master  ffacd62 chore: baseline H5 prototype and first native milestone
develop 6fb7ffd chore: preserve full handoff state on develop
        （其后的分层、设计系统、GPU 预览、数值/格式/i18n 增量为线性提交；
         以 `git log --oneline --decorate develop` 为准）
```

## 提交约定

使用 Conventional Commits 前缀，一次提交只做一件事：

```text
feat(ui): add motion tokens and NekoButton
fix(io): reject oversized images before decode
refactor(document): extract history budget
docs(adr): record GPU preview decision
test(render): compare shader mirror with CPU pipeline
build: add optional Rust module gate
```

提交前必须：

1. `cmake --build` 无新增警告；
2. `ctest --output-on-failure` 通过；
3. QML 测试通过；
4. `git diff --check` 无输出；
5. 文档中的「已实现 / 未实现 / 未验证」状态与实际一致。

## 并行规则

- 每个工作流只改自己拥有的文件集（见 `docs/architecture/module-map.md`）。
- 公共接口、CMake、`Main.qml`、翻译由集成负责人统一修改。
- 工作流在独立 worktree 中开发，合并前先 rebase/merge `develop` 并重跑测试。
- 禁止 `git push --force`、禁止提交构建目录、禁止删除他人的未跟踪文件。

## 一键校验

```sh
./scripts/check.sh                # 默认 native/build-check
./scripts/check.sh native/build-ci  # 指定构建目录
./scripts/check-source-size.sh    # 文件体积预算（--strict 为发布门禁）
./scripts/validate-packaging.sh   # desktop/AppStream/图标（--strict 为发布门禁）
```

`check.sh` 依次执行配置、构建、C++ 测试、QML 测试和空白检查；后两个脚本
分别检查源码体积和打包元数据，CI 已接入。CI 环境应使用独立构建目录，`NEKOPIC_WITH_RUST` 默认关闭，另跑一次 `ON` 验证可选模块。

GPU/着色器路径另跑一次 RHI：

```sh
QT_QPA_PLATFORM=offscreen QSG_RHI_BACKEND=opengl QT_QUICK_BACKEND=rhi \
  /usr/lib/qt6/bin/qmltestrunner -input native/qml/tests -silent
```

视觉回归使用离屏抓图（不依赖合成器醒着）：

```sh
./scripts/screenshot.sh assets/demo.jpg artifacts/dark.png dark
./scripts/screenshot.sh assets/demo.jpg artifacts/light.png light
# 直接打开某个工具或设置页（开发钩子）
QT_QPA_PLATFORM=offscreen ./native/build/nekopic assets/demo.jpg --tool filters --screenshot artifacts/filters.png
QT_QPA_PLATFORM=offscreen ./native/build/nekopic assets/demo.jpg --settings --screenshot artifacts/settings.png
```

## 打包

安装规则、CPack（TGZ/DEB/RPM）、AppImage、图标生成、元数据校验与发布清单
见 [打包与发布](packaging.md)。一键 Release 打包：

```sh
./scripts/package.sh
./scripts/build-appimage.sh --stage-only   # 无 linuxdeploy 时校验 AppDir
```

## 代码风格

- C++：`.clang-format`（LLVM 基础，4 空格，100 列）。
- QML/JS：`.editorconfig`，4 空格；组件以 `Neko` 前缀进入 `qml/UI`。
- 命名与体积约定见 `docs/architecture/module-map.md`。
- 注释解释意图、坐标、线程契约，不复述代码。
