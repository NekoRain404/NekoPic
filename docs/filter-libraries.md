# NekoPic 调色与滤镜选型

本阶段先验证界面。新增高级调色不接入图像处理，12 款滤镜仅复用现有基础调色参数做演示，不代表最终效果质量。

## 官方资料核对

2026-11-04 直接访问官方网站和仓库源码核对。当前环境没有可用的搜索引擎工具，GitHub API 请求返回 403；以下结论来自可访问的一手页面，而非搜索摘要。

| 方案 | 适合做什么 | 许可证与边界 | 对 NekoPic 的建议 |
| --- | --- | --- | --- |
| G’MIC / libgmic | C++ 集成，提供丰富的图像处理、艺术效果与滤镜命令 | 核心 `src/gmic.h` 明确为 CeCILL-C 或 CeCILL v2.1 二选一，分别近似 LGPL / 与 GPL 兼容；其他组件、插件和预设资源需按各自许可核对 | 最值得试验的丰富滤镜后端；筛选少量常用效果，封装成本地预设，不向用户暴露庞大的命令参数 |
| libvips | 高效图像处理，尺寸变换、颜色操作与文件输出；提供 ICC 变换接口 | 官方声明 LGPL-2.1-or-later；实际文件格式与 ICC 支持受构建依赖影响 | 候选基础处理库，不是开箱即用的手机滤镜合集；预设需自行设计 |
| glfx.js | 浏览器 WebGL 图像效果预览 | MIT；较早的项目，当前浏览器与 GPU 兼容性仍需实测 | 可用于增强 HTML 原型，不建议将其作为 Linux 原生产品的核心处理引擎 |

一手来源：

- [G’MIC 官网与下载说明](https://gmic.eu/download.html)
- [libgmic 核心头文件与完整许可声明](https://github.com/GreycLab/gmic/blob/master/src/gmic.h)
- [libvips 官网：处理能力与许可证](https://www.libvips.org/)
- [libvips LICENSE](https://github.com/libvips/libvips/blob/master/LICENSE)
- [libvips ICC transform API](https://www.libvips.org/API/current/method.Image.icc_transform.html)
- [glfx.js 官方演示](https://evanw.github.io/glfx.js/)
- [glfx.js MIT LICENSE](https://github.com/evanw/glfx.js/blob/master/LICENSE)

## 推荐路线

先以自有参数预设实现清透、暖调、柔光、胶片、黑白等常用风格，再支持 `.cube` LUT 扩展。LUT 是色彩映射数据格式，不是滤镜库，也不能独立实现颗粒、锐化、暗角和空间模糊；第三方 LUT 文件还需要单独确认再分发许可。

原生阶段先对 libvips 做基础操作、色彩转换和导出的验证；只有确实需要更多艺术效果时再加入 libgmic。两者职责可以分开，也不必首版同时引入。是否采用需要用大图预览延迟、内存、取消响应和最终导出一致性测试决定。

ICC 管理独立于风格滤镜：解码并处理 EXIF 方向 → 按输入 ICC 转到工作色域 → 基础调色与风格处理 → 对象合成 → 按目标色域转换并输出。LUT 的输入 / 输出色域必须明确，不能把 Display P3、AdobeRGB 像素直接当成 sRGB。预览和最终导出必须共享参数与处理顺序。

## 交互约定

- 调色分为基础 / HSL / 曲线 / 色彩分级 / 细节与效果，保留当前页签、通道与参数。
- 滤镜一次选择一个，强度独立，基础调色不被清空。收藏按钮不会应用滤镜。
- 原图对比复用顶部按住对比与 M 键。移除滤镜保留基础调色。
- 当前高级参数只在 UI 中暂存，不计入撤销、保存、崩溃恢复；正式接入时一次拖动对应一次撤销。
- 正式实现需在打开新图片时初始化独立参数；风格缩略图改用当前图片的低分辨率渲染，并缓存结果。
