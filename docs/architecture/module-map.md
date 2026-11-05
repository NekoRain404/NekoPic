# 模块地图与文件约定

## 目录结构（目标）

```text
NekoPic/
├── docs/
│   ├── architecture/          架构方向与模块地图
│   ├── adr/                   架构决策记录
│   └── roadmap.md             阶段与并行工作流
├── docs/superpowers/specs/    设计评审稿（如需）
├── native/
│   ├── cmake/                 构建辅助（Rust 可选集成、测试注册）
│   ├── shaders/               GLSL 源文件，经 qsb 编译进资源
│   ├── rust/                  可选 Rust crate（默认不参与构建）
│   ├── src/
│   │   ├── core/              纯图像算法：adjustments/colorpipeline、mosaic、blur、histogram、autoenhance、filterpresets
│   │   ├── io/                imageio、formatregistry、可选 rustcodecs
│   │   ├── document/          文档模型、命令、历史（从控制器逐步提取）
│   │   ├── render/            预览后端、能力探测、CPU/GPU 一致性
│   │   ├── platform/          剪贴板、最近文件、系统集成
│   │   └── app/               QML 桥接、控制器、入口、设置、语言与主题
│   ├── qml/
│   │   ├── UI/                设计令牌单例与通用控件
│   │   ├── effects/           GPU 预览 QML 包装
│   │   ├── components/        HistogramView 等通用可视化
│   │   ├── inspector/         五页签调色子组件（slider/HSL/曲线/分级）
│   │   ├── panels/            画笔、形状、打码等属性面板
│   │   ├── filters/           滤镜网格、分类、搜索与收藏
│   │   ├── canvas/            画布与视口
│   │   ├── panels/            属性面板
│   │   ├── overlays/          裁剪、马赛克等手势层
│   │   ├── shell/             窗口、菜单、工具栏
│   │   └── tests/             QML 测试
│   ├── tests/                 C++ 测试
│   └── i18n/                  翻译源与产物
└── (根目录 H5 原型，保留作视觉参考)
```

迁移按增量进行：现有文件不一次性搬空，先保证 `core/io/document/render/platform/app` 的依赖方向成立，再移动 QML。

## 命名与体积

| 对象 | 约定 |
| --- | --- |
| C++ 源文件 | `snake_case.cpp/.h`；一个文件一个主要职责 |
| C++ 类型 | `PascalCase`；接口用 `I` 前缀或 `XxxService` 语义名 |
| 控制器 | `documentcontroller_<能力>.cpp` 按职责拆分 |
| QML 组件 | `PascalCase.qml`；单例放 `qml/UI` 并在 `qmldir` 注册 |
| QML 测试 | `tst_<组件>.qml` |
| C++ 测试 | `tst_<模块>.cpp` 或 `<模块>_test.cpp` |
| 信号 | 过去式事实（`documentChanged`）；命令用祈使式 |
| 属性 | 名词/形容词，只读暴露 + NOTIFY |

体积软上限：单文件约 300 行、单函数约 60 行；超出时按职责拆分，而不是机械切块。禁止一个控制器继续吸收所有能力。

## 所有权与并行

- 集成分支负责人：CMake、`main.cpp`、`Main.qml`、翻译、公共控制器接口。
- UI 工作流：`qml/UI`、`qml/effects` 的组件与测试。
- 渲染工作流：`src/render`、`shaders/`、对应测试。
- 格式/Rust 工作流：`src/io/formatregistry`、`rust/`、可选桥接与测试。
- 文档模型工作流：`src/document`、历史提取、对象模型。

并行规则：每个工作流拥有独立文件集；公共接口变更由集成负责人先落地；禁止多个工作流同时改 `Main.qml`、`CMakeLists.txt` 或同一控制器文件。

## 依赖规则检查

- `core` 只依赖 Qt Core/Gui，不依赖 Quick、Concurrent、QML。
- `io` 依赖 Core/Gui，可选依赖 Rust 静态库；不依赖 QML。
- `render` 依赖 Core/Gui/Quick；不反向依赖 `app`。
- `document` 不依赖 `app`；`app` 组合文档与服务。
- QML 只通过 context property / 注册类型调用 `app` 层。
