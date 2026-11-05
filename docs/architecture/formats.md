# 格式能力与导出策略

状态：2026-11-05 在本机实测（Qt 6.12，安装 `qtimageformats` + `kimageformats`）。
其他发行版/打包方式可能不同，发布前必须在目标环境重新生成矩阵。

## 1. 能力来源

`NekoPic::Io::FormatRegistry` 在运行时读取：

- `QImageReader::supportedImageFormats()` — 可读取；
- `QImageWriter::supportedImageFormats()` — 可写出。

界面（打开对话框、导出格式列表）只使用注册表结果，不硬编码扩展名。扩展名与格式 id 的映射、首选后缀（`jpeg` → `jpg`、`tiff` → `tif`）也由注册表提供。

## 2. 本机矩阵（摘要）

| 能力 | 数量 | 代表格式 |
| --- | ---: | --- |
| 读取 | 101 | PNG、JPEG、WebP、TIFF、GIF、BMP、ICO、TGA、QOI、AVIF、HEIC/HEIF、JPEG XL、JPEG 2000、PSD/PSB、EXR、HDR、DDS、PCX、SGI、PNM、SVG、XCF、PDF、多种相机 RAW |
| 写出 | 38 | PNG、JPEG、WebP、TIFF、BMP、ICO、TGA、QOI、AVIF、HEIC/HEIF、JPEG XL、JPEG 2000、EXR、PNM、XBM/XPM、DDS、PCX、SGI |

注意事项：

- RAW 通常只能读取，且解码质量/元数据取决于插件；不能承诺编辑后回写 RAW。
- GIF/PSD/SVG/PDF 等“读取”不等于可完整编辑；动画、多页、矢量语义不在当前模型内。
- AVIF/HEIC/JXL 等写入依赖插件与编解码器；是否可用以注册表为准，失败由 `QImageWriter` 错误上报。
- 文件对话框按实际能力过滤，但用户仍可能通过“所有文件”选择不支持的内容，由解码错误处理。

## 3. 导出策略

1. **PNG**：默认无损输出；保留 alpha、位深与 `QColorSpace` 标签。
2. **JPEG**：无 alpha；透明区域按用户选择的背景色合成（默认白色）；质量可在导出对话框中调整。
3. **其他可写格式**：只要 `QImageWriter` 报告支持就出现在导出列表；质量参数按编解码器语义传递（`-1` 表示默认）。
4. **不重编码未修改的原文件**：直接复制/提交会保留原编码；只有实际编辑后才重新编码。
5. **元数据**：当前不主动嵌入 ICC/EXIF；界面必须明确说明这一限制，不能称为“完整色彩管理”或“保留元数据”。

## 4. 色彩与位深边界

- 解码后尽量保留 `QImage` 表示与 `QColorSpace` 标签；调色/马赛克有 16 位/浮点分支。
- 滤镜缩略图会转为 8 位 RGBA，仅用于预览，不代表导出质量。
- 当前工作流按编码值计算，未实现线性光、显示器 ICC 读取与输出色域转换。
- JPEG 重新编码有损；PNG 16 位与广色域配置已有往返测试，但整条链路不能据此称为无损。

## 5. 重新生成矩阵

```sh
# 运行时能力（与 FormatRegistry 一致）
QT_QPA_PLATFORM=offscreen ./native/build/formatregistry_test -vs 2>/dev/null || true

# 或使用任意 Qt 程序打印：
# QImageReader::supportedImageFormats()
# QImageWriter::supportedImageFormats()
```

发布前至少验证：PNG（8/16 位、alpha、ICC）、JPEG（透明合成、质量）、WebP（读写）、TIFF（读写）、AVIF/HEIF/JXL（若宣称支持）。未验证的格式不得写入 README 的支持承诺。
