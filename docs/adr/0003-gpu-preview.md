# ADR-0003：GPU 交互预览，CPU 权威提交

状态：已采纳（2026-11-05）；同日扩展高级基础调色覆盖

## 背景

拖动调色滑杆时，当前实现每次参数变化都排队 CPU worker，大图上反馈受线程调度与内存拷贝限制。Qt Quick 已由 RHI 硬件加速显示，可在 GPU 上即时预览。

## 决策

- 交互期间：以**底图**（未应用调色/滤镜）为基础，用着色器按待提交参数即时渲染；不触发 CPU 预览 worker。
- 松手后：CPU 生成权威像素，提交撤销历史，替换预览。
- 启用条件：非软件渲染后端、着色器可用、无滤镜叠加（滤镜会先落到 `image_`，底图不含滤镜），且当前参数全部落在着色器覆盖范围内（`isGpuPreviewSupported`）。否则回退现有 CPU 预览。
- 着色器与 `core/colorpipeline.cpp` 的 `applyExtended` 融合逐像素阶段使用同一公式；提供 CPU 镜像实现与容差测试。
- 导出与保存永远使用 CPU 结果。

## 着色器覆盖范围

以下 11 个键由 `isGpuPreviewKey` 判定为 GPU 可预览，并作为 ShaderEffect uniforms 从 `pendingAdjustmentValues` 传入：

| 阶段 | 键 | 着色器实现 |
| --- | --- | --- |
| 白平衡 | `temperature`, `tint` | 通道增益 `(1+0.30T+0.10t, 1-0.20t, 1-0.30T+0.10t)` |
| 影调 | `exposure`, `brightness`, `contrast` | `(v·2^E − 0.5)·(1+C) + 0.5 + B`，随后 clamp01 |
| 影调遮罩 | `highlights`, `shadows`, `whites`, `blacks` | 与 CPU 相同的 smoothstep 掩码、亮度权重与 `0.5·(…)` 增量 |
| 色彩 | `saturation`, `vibrance` | 先饱和度后自然饱和度；HSV 饱和度和亮度权重与 CPU 一致 |

顺序与 `applyExtended` 完全一致：白平衡 → 影调与截面遮罩（每步 clamp01）→ 饱和度 → 自然饱和度（末次 clamp01）。当没有任何高级键激活时，着色器保留原有四键公式，避免改变历史基础路径的像素。

`exposure` 的 UI 值到 shader uniform 的映射为 `ui / 25` = 光圈档数（存储值为 `ui × 0.04`）；其它键为 `ui / 100`。

## 仍为 CPU-only 的阶段

以下参数激活时 `isGpuPreviewSupported` 返回 false，交互预览回退 CPU：

- HSL 八个色带；
- 曲线（RGB/R/G/B）；
- 色彩分级（任一区域饱和度或明度非零；仅色相/混合/平衡不改变像素，可继续 GPU）；
- 细节与效果：`texture`, `clarity`, `dehaze`, `sharpen`, `noise`, `colorNoise`；
- 效果尾段：`vignette`, `grain`, `fade`；
- 滤镜预设（同时由 QML 侧 `filterPreset === "none"` 条件拦截）。

这些阶段需要邻域采样、LUT、逐通道曲线或多阶段混合，当前不值得为预览重复实现；松手后的 CPU 提交会补齐最终外观。

## 一致性容差

- CPU 镜像（`render/previewmath`）与权威 CPU 对比：8 位通道 ≤ 2/255，16 位通道 ≤ 2/65535。两者均为 double 运算，差异只来自 CPU 内部的 16 位量化与格式转换顺序。
- GPU 实际渲染与 CPU 对比（QML readback 测试）：≤ 4/255。32 位浮点、`smoothstep`/`dot` 的求值顺序以及纹理 8 位存储造成少量舍入差；4/255 不会掩盖公式错误（错误公式在该测试色上偏移远大于此）。
- 测试覆盖：`tests/tst_previewmath.cpp` 对新增键做单项、组合与极值 CPU 镜像对比；`qml/tests/tst_adjustment_preview.qml` 在可回读像素的后端上做 GPU/CPU 对比。

## 后果

- 正面：拖动反馈与界面同帧率，减少后台任务与内存峰值；常用高级基础滑杆同样即时。
- 正面：GPU 单 pass 只增加常数量级 ALU 运算，不增加纹理采样或额外 pass。
- 代价：需要维护着色器/CPU 两套公式与一致性测试。
- 风险：不同 RHI 后端（OpenGL/Vulkan/Metal/D3D）行为差异；以能力探测和真实设备抽查控制。无法回读像素的后端会跳过 GPU 像素一致性测试，但着色器仍参与正常渲染。
