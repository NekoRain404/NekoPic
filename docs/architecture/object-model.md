# 对象模型设计（前瞻契约）

状态：**内核已实现，尚未接入文档控制器/QML**（2026-11-05）。`native/src/document/object*` 提供文字、形状、笔迹、层级、命中测试、变换与裁剪，并有 20 个测试；本文其余部分约束控制器与工具接入时的行为。

## 1. 为什么需要对象

现在的文档状态是「底图 + 参数 + 合并结果」。一旦加入文字/形状/笔迹，必须能：

- 独立编辑、选中、排序、删除对象；
- 撤销/重做以事务为单位；
- 旋转/翻转/裁剪/缩放时对象与像素保持一致；
- 保存合并图，但会话内保留可编辑对象；
- 崩溃恢复时能重建对象（恢复快照，不是工程格式）。

## 2. 文档结构

```text
Document
├── id, revision, savedRevision
├── sourceImage        解码并应用方向的原始像素（只读）
├── geometry           crop / rotate / flip / canvas size 的累积描述
├── adjustments        基础调色、滤镜参数（非破坏性）
├── objects[]          有序对象列表（z-order 由顺序决定）
├── maskLayers[]       马赛克/模糊等像素操作层（可选）
└── history            命令事务快照
```

`DocumentSnapshot` 是不可变值：持有 `shared_ptr<const ImageData>`、对象列表副本、几何与参数。worker 只接收快照，不接触 GUI 文档。

## 3. 对象基类

```text
DocumentObject
├── id (stable, monotonic)
├── type (text | shape | stroke | sticker)
├── transform: position, rotation, scale, flip
├── opacity, blendMode, visible, locked
├── bounds() -> QRectF (文档像素坐标)
├── render(QPainter&, const RenderContext&)
└── clone()
```

具体对象：

- `TextObject`：多行文本、字体族/字重/字号、行距、对齐、颜色、描边、内边距；Linux 中文字体回退必须显式测试。
- `ShapeObject`：矩形、椭圆、直线、箭头、多边形；填充/描边/圆角；Shift 等比或角度约束。
- `StrokeObject`：点序列 + 笔刷参数（直径、硬度、间距、压力）；一笔一个对象或一次事务。
- `StickerObject`：图像资源 + 变换。

对象只存参数与矢量/笔迹数据，不烘焙像素。栅格化只在预览或导出时发生，保证缩放/重做质量。

## 4. 坐标与几何规则

统一使用**文档图像像素坐标**（连续值，左上原点，y 向下）。QML 负责视图/显示坐标映射。

| 操作 | 像素 | 对象 |
| --- | --- | --- |
| 旋转/翻转 | 变换底图与合并图 | 同一变换作用于对象坐标与旋转角 |
| 裁剪 | 复制选区像素 | 坐标平移，裁剪区外对象被裁掉或删除（按相交判定） |
| 图片尺寸缩放 | 重采样像素 | 位置、尺寸、笔迹按同一比例缩放 |
| 画布尺寸扩展 | 新增透明/背景像素 | 对象按锚点平移，不缩放 |
| 移动对象 | — | 只改对象 transform |

规则：先构造几何变换矩阵，再对像素与对象分别应用同一矩阵；禁止对象与像素各写一套公式。

## 5. 命令与撤销

所有修改通过命令：

```text
Command
├── apply(DocumentState&) -> DocumentState
├── undo(DocumentState&) -> DocumentState
└── mergeWith(Command&) -> bool   // 滑杆连续拖动、文本输入合并
```

- 一次滑杆拖动、一笔绘制、一段文字编辑 = 一次事务；中间帧只更新预览。
- 历史项保存不可变快照或轻量 diff；图像数据用 `shared_ptr` 去重，沿用 256 MiB 预算。
- 预览与提交共用同一命令参数，避免预览/结果不一致。

## 6. 选择与命中测试

- `hitTest(point, tolerance)` 从上到下遍历 z-order；文字命中用排版后的行框，形状用路径，笔迹用线段距离。
- 多选时支持对齐、分布、层叠顺序；变换以选区包围盒为基准。
- 选择态属于 UI 状态，不进入文档历史；但「删除/移动选中对象」是命令。

## 7. 保存、导出与恢复

- 保存/另存为输出**合并图**：源图 → 几何 → 调色/滤镜 → 马赛克层 → 对象合成 → 输出色彩转换。
- 保存成功后保留对象与参数，`savedRevision` 更新；继续编辑重新变脏。
- 重新打开合并图时对象不可编辑，界面必须提示，不得暗示仍可编辑。
- 恢复快照包含对象数据、版本号、完整性校验与写入限额；它不是工程格式，也不是备份。

## 8. 并行开发边界

| 工作流 | 交付 |
| --- | --- |
| 文档模型 | `DocumentState`、`Command`、历史、快照序列化 |
| 文字工具 | `TextObject`、字体回退、排版与编辑框 |
| 形状工具 | `ShapeObject`、路径构建、Shift 约束 |
| 画笔工具 | `StrokeObject`、采样/防抖/压感 |
| 渲染 | 对象合成、预览缓存、与导出共享管线 |
| UI | 选中框、变换手柄、图层面板、属性面板 |

集成负责人先落地 `DocumentObject` 接口、命令协议与 `DocumentSnapshot`，再允许各工具并行；禁止各自修改文档状态结构。

## 9. 验收样例

- 旋转 90° 后文字方向与位置正确，撤销恢复；
- 裁剪后对象坐标平移，区外对象不残影；
- 图片缩放后笔迹粗细按比例变化；
- 文字编辑一次撤销，不发散为每字符一项；
- 保存后继续编辑对象，脏状态正确；
- 恢复快照损坏时安全拒绝并提示。


## 10. 已实现内核 API（2026-11-05）

代码位于 `native/src/document/`，测试为 `native/tests/tst_objects.cpp`（20 项）。

| 类型 | 关键接口 |
| --- | --- |
| `DocumentObject` | `id()`, `kind()`, `visible/locked/opacity`, `transform/translation`, `applyTransform`, `bounds`, `render`, `hitTest`, `clone` |
| `TextObject` | `text`, `font`/`fontFamily`/`fontWeight`/`fontPointSize`, `color`, `alignment`, `lineHeight`, `outlineColor`/`outlineWidth`, `padding` |
| `ShapeObject` | `shape`（矩形/椭圆/直线/箭头/多边形）, `rect`/`points`, `fillColor`/`strokeColor`/`strokeWidth`, `cornerRadius` |
| `ShapeGeometry` | `squareFromDrag`, `snapToAngle`（Shift 约束） |
| `StrokeObject` | `points`/`addPoint`/`clearPoints`, `MaxSamples = 4096`, `diameter`, `color` |
| `ObjectLayer` | `add`/`take`/`remove`/`clear`, `object`/`objectAt`/`hitTest`, `raise`/`lower`/`bringToFront`/`sendToBack`/`moveTo`, `renderOnto`, `applyTransform`, `crop` |

已知限制：文字为矢量轮廓、无自动换行/富文本/光标模型；变换为仿射；笔迹 4096 采样上限；命中测试在非均匀缩放下为近似；`crop` 不做对象级破坏性裁剪。控制器接入与文字/形状/笔迹工具界面是下一步。
