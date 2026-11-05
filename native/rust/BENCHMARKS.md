# Rust advantage benchmarks (ADR-0002 evidence)

Status: research record, 2026-11-05. **No Rust crate or C++ bridge is shipped as a result of this spike.**
Related decision: [`docs/adr/0002-rust-boundary.md`](../../docs/adr/0002-rust-boundary.md).

## Decision

**Do not introduce Rust into NekoPic now.** None of the three sanctioned candidate roles clears
the ADR-0002 bar in a way that matters to the current product.

Bar used for this evaluation:

- a capability Qt genuinely lacks, or
- more than 20% wall-clock speedup at equal quality on a path the product actually uses.

Summary:

| Candidate | Result | Verdict |
| --- | --- | --- |
| A. EXIF/metadata parsing | Qt already exposes orientation via `QImageReader::transformation()` and ICC via `QColorSpace`. `kamadak-exif` parses the fixture in about 1 µs, but NekoPic has no consumer for other EXIF tags. | No product win. |
| B. Extra format decode | This Qt 6.12 build reads 101 formats and writes 38, including TIFF, WebP, GIF, BMP, ICO, AVIF, HEIF, JXL, JPEG 2000, PSD, EXR, HDR, QOI, TGA and camera RAW. The `image` crate reads 7 formats. Qt is a strict superset here. | No capability gap. |
| C. SIMD resize for thumbnails | `fast_image_resize` is 1.1-2.1x faster than `QImage::scaled(..., SmoothTransformation)` for 12 MP sources at targets >= 512 px, and 1.2-2.1x faster for the 1.8 MP demo. At the product's actual preview size (192x144) the win is 22% on the 1.8 MP demo (0.5 ms), 10% on 12 MP, and -4% on 48 MP. The large-target wins on 12 MP come with PSNR 31-38 dB versus Qt smooth, so "equal quality" is not established there. | Conditional, not material for the current 192 px preview path. |
| Bonus: JPEG decode | Qt/libjpeg-turbo is 1.28x faster on the 2.2 MP demo; Rust is 1.08x faster on a 24 MP JPEG (below the 20% bar). Decoded pixels agree at 56-62 dB PSNR. | No material win. |
| Bonus: PNG decode | `image`'s PNG decoder is 2.27x faster than Qt/libpng, but this is not an "extra format" (Qt already reads PNG), would replace Qt's default decode path, and would pull in the 44-package `image` dependency tree. | Not pursued; revisit only if PNG open time becomes a measured bottleneck. |

The resize data does contain real wins. They are not cherry-picked away: the full table is below.
They simply do not apply to the only resize call site in the product today
(`native/src/app/filterpreviews.cpp`: `source.scaled(192, 144, ..., SmoothTransformation)`),
where the absolute saving is under 1 ms on the demo and negative on 12 MP/48 MP sources.

Revisit this decision if one of the following becomes a measured product requirement:

- user-facing resize/downscale/export at >= 512 px from <= 12 MP sources;
- PNG open latency becomes a user-visible bottleneck (worth a separately scoped decoder spike);
- Qt loses its image-format plugins in a target distribution.

## Environment

| Item | Value |
| --- | --- |
| CPU | Intel Core Ultra 7 258V, 8 logical CPUs (4 P-cores up to 4.8 GHz, 4 LP E-cores up to 3.7 GHz), AVX2/BMI2/FMA, no AVX-512 |
| Governor | `powersave` (intel_pstate active); observed scaling around 1.5 GHz, turbo enabled |
| OS / kernel | Arch Linux, kernel `7.2.14-zen1-1-zen`, glibc 2.44 |
| Compiler | GCC 16.2.1 |
| CMake / Ninja | CMake 4.4.5, Ninja 1.13.2 |
| Qt | 6.12.0 (qt6-base 6.12.0-3), installed `qtimageformats` + `kimageformats` plugins |
| Qt JPEG backend | libjpeg-turbo 3.2.1 (`libjpeg.so.8`) |
| Qt PNG backend | libpng 1.6.59 |
| Rust | rustc/cargo 1.99.1, `x86_64-unknown-linux-gnu` |
| Rust crates | `fast_image_resize` 6.1.0 (auto-selected AVX2), `image` 0.25.10, `kamadak-exif` 0.6.1 |
| Host load | shared machine, load average 9-12 and all cores 75-93% busy during runs (other builds); see methodology |

The host was heavily contended by unrelated compiler processes for the whole measurement window.
This is why the methodology uses interleaved Qt/Rust process runs and reports both a
median-of-medians and a min-of-min cross-check. Differences below roughly 10-15% should be
treated as noise on this machine.

## Methodology

Fixtures:

- `assets/demo.jpg`: real photo, 1800x1200, progressive JPEG, 482,856 bytes.
- `synth-4000x3000.png`: 12 MP synthetic image (gradient + fine LCG noise + checker detail), lossless PNG.
- `synth-8000x6000.png`: 48 MP synthetic image, same generator, lossless PNG.
- `synth-6000x4000.jpg`: 24 MP synthetic JPEG, Qt encoder quality 92 (`synth-6000x4000.jpg`, 36 MB).
- `demo-1800x1200.png`: lossless copy of the demo so Qt and Rust resize start from identical pixels.
- `orientation{1,3,6,8}.jpg`: demo plus EXIF Orientation/Make/Model/Software written with Pillow 13.0.0.

Timing:

- Wall clock via `std::chrono::steady_clock` in both tools.
- Per process: 3 warmup iterations, then 9 measured iterations; report the median.
- Three interleaved process rounds: Qt then Rust for round 1, Rust then Qt for round 2, Qt then Rust for round 3.
  The value in the primary tables is the median of the three per-process medians.
- The min-of-min table is the fastest single iteration observed across the three processes; it is a
  lower-bound cross-check against scheduler noise.
- Both tools pinned with `taskset -c 1`. Qt used `QT_QPA_PLATFORM=offscreen`; `QGuiApplication` was
  created so image plugins were discoverable.
- Resize buffers: Rust used `PixelType::U8x4` with `mul_div_alpha = true`, matching QImage's
  `Format_RGB32` (4 bytes per pixel, alpha 255) without any conversion at the boundary.
  This deliberately avoids a hidden RGB32->RGB888 conversion that would erase a speedup.
- Source image is decoded once outside the timed region. Each timed iteration allocates a fresh
  destination, like `QImage::scaled` does.
- PSNR is computed on the full RGB output against the Qt smooth result; all outputs are RGB888.

Scratch code (not part of the repository, not committed):

```text
/tmp/nekopic-spike/rustbench/          # Cargo bench crate
/tmp/nekopic-spike/qtbench/            # Qt baseline probe and benchmark
/tmp/nekopic-spike/scripts/            # fixture, interleave, PSNR scripts
```

Commands (abridged):

```bash
# Qt format matrix and EXIF transformation probe
QT_QPA_PLATFORM=offscreen ./qtprobe assets/demo.jpg

# decode: Qt then Rust, args = file warmup runs raw-out
taskset -c 1 env QT_QPA_PLATFORM=offscreen ./qtbench decode assets/demo.jpg 3 9 out/qt_demo.raw
taskset -c 1 ./nekopic-rust-bench decode assets/demo.jpg 3 9 out/rust_demo.raw

# resize: u8x4 matches QImage RGB32; 3 warmup + 9 runs per target/filter
taskset -c 1 env QT_QPA_PLATFORM=offscreen ./qtbench resize data/synth-4000x3000.png 3 9 out
taskset -c 1 ./nekopic-rust-bench resize data/synth-4000x3000.png 3 9 out u8x4 true
```

## Qt 6.12 baseline format matrix

Runtime enumeration via `QImageReader::supportedImageFormats()` / `QImageWriter::supportedImageFormats()`
with `QT_QPA_PLATFORM=offscreen`:

- Read: **101** formats
- Write: **38** formats

Readable and writable: `png`, `jpeg`/`jpg`, `bmp`, `tiff`/`tif`, `webp`, `ico`, `tga`, `qoi`,
`avif`, `heic`/`heif`, `jxl`, `jp2`/`j2k`, `exr`, `ppm`/`pgm`/`pbm`, `xbm`/`xpm`, `dds`, `pcx`,
`sgi`, `wbmp`, `eps`, `rgb`/`rgba`, `pic`, `jfif`.
Read-only notable: `gif`, `psd`/`psb`, `hdr`, `svg`, `xcf`, `pdf`, `farbfeld`, and camera RAW
formats (`arw`, `cr2`, `cr3`, `dng`, `nef`, `orf`, `raf`, `rw2`, and others).

Full read list:

```text
3fr ani arw avci avif avifs bmp bw cr2 cr3 crw cur dcr dds dng eps epsf epsi erf exr ff fff gif
hdp hdr heic heif hej2 hif icns ico iff iiq ilbm im1 im24 im32 im8 j2k jfif jp2 jpeg jpf jpg jxl
jxr k25 kdc kra lbm mdc mef mos mrw nef nrw ora orf pbm pcx pdd pdf pef pfm pgm phm pic png ppm
psb psd psdt pxr qoi raf ras raw rgb rgba rw2 rwl sct sgi sr2 srf srw sti sun svg svgz tga tif
tiff tim wbmp wdp webp x3f xbm xcf xpm
```

Full write list:

```text
avci avif bmp bw cur dds eps epsf epsi exr heic heif icns ico j2k jfif jp2 jpeg jpg jxl jxr pbm
pcx pgm pic png ppm qoi rgb rgba sgi tga tif tiff wbmp webp xbm xpm
```

The scratch crate enabled only `jpeg`, `png`, `bmp`, `tiff`, `gif`, `webp` and `ico`, so `image`
read 7 formats. Even with every default format feature enabled it reads at most 14 formats
(`avif`, `bmp`, `exr`, `farbfeld`, `gif`, `hdr`, `ico`, `jpeg`, `png`, `pnm`, `qoi`, `tga`,
`tiff`, `webp`), still a strict subset of Qt's 101 and missing HEIF, JXL, JP2, PSD, SVG and RAW.
It cannot replace the Qt plugin set.

## Candidate A: EXIF/metadata

Qt has no public API for arbitrary EXIF tags, but the two needs named in the brief are already covered:

- Orientation: `QImageReader::transformation()` returns `QImageIOHandler::TransformationRotate90`
  (value 4) for an EXIF Orientation=6 fixture. `imageio.cpp` already calls `setAutoTransform(true)`,
  so orientation is applied on load.
- ICC: decoded images carry a `QColorSpace`; `imageio.cpp` preserves it on save and Qt applies it on load.

`kamadak-exif` correctly reported Orientation=6 (`row 0 at right and column 0 at top`), Make=NekoPic,
Model=BenchCam from the same fixture.

Parse timing (in-memory, 20 warmup + 200 runs, 524,056-byte JPEG): median **0.99 µs**, min 0.98 µs,
max 12.05 µs. Parse cost is irrelevant compared with decode (tens of milliseconds).

Verdict: the library is safe and fast, but there is no product requirement it satisfies that Qt does
not already satisfy. Adding a Rust dependency and FFI surface for unused metadata tags is not justified.

## Candidate B: extra format decode

Qt in this environment is a strict superset of the `image` crate for the formats that matter
(PNG, JPEG, TIFF, WebP, GIF, BMP, ICO) and additionally reads AVIF, HEIF, JXL, JP2, PSD, EXR, HDR,
QOI, TGA, DDS, PCX, XCF, SVG and many camera RAW formats. There is no format in the candidate list
that Qt cannot decode here. Verdict: no capability win, so no Rust decoder is added.

## Candidate C: resize / thumbnail downsample

`QImage::scaled(target, Qt::IgnoreAspectRatio, ...)` versus `fast_image_resize` 6.1.0.
All values are milliseconds; lower is better. `Box` is the quality-equivalent filter to Qt's
area-style `SmoothTransformation`; `Bilinear` and `Lanczos3` are shown for context.
`BilinearInterp` is `ResizeAlg::Interpolation(Bilinear)` (fixed 2x2 kernel); it is fastest but
aliases on large downscales and is not quality-equivalent.

### Primary results (median of 3 interleaved process medians; 3 warmup + 9 runs each)

| Source | Target | Qt Fast | Qt Smooth | FIR Box | FIR Bilinear | FIR Bilin-Interp | FIR Lanczos3 | Qt Smooth / FIR Box |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| demo 1800x1200 (2.2 MP) | 192x128 | 0.03 | 2.59 | 2.10 | 2.32 | 1.56 | 4.39 | 1.23x |
| demo 1800x1200 | 256x170 | 0.05 | 3.06 | 2.17 | 2.32 | 1.67 | 4.48 | 1.41x |
| demo 1800x1200 | 512x341 | 0.26 | 4.23 | 2.57 | 2.91 | 2.27 | 5.12 | 1.64x |
| demo 1800x1200 | 1024x682 | 0.82 | 7.99 | 3.86 | 4.21 | 4.34 | 7.62 | 2.07x |
| synth 4000x3000 (12 MP) | 192x144 | 0.05 | 11.65 | 10.64 | 12.67 | 7.47 | 24.35 | 1.09x |
| synth 4000x3000 | 256x192 | 0.17 | 12.20 | 10.77 | 12.59 | 7.73 | 24.20 | 1.13x |
| synth 4000x3000 | 512x384 | 0.49 | 15.02 | 11.29 | 13.66 | 8.89 | 24.59 | 1.33x |
| synth 4000x3000 | 1024x768 | 1.59 | 21.43 | 13.09 | 14.78 | 11.64 | 26.84 | 1.64x |
| synth 4000x3000 | 1920x1440 | 3.59 | 40.20 | 17.59 | 19.31 | 17.65 | 32.60 | 2.29x |
| synth 8000x6000 (48 MP) | 192x144 | 0.07 | 43.33 | 46.10 | 59.03 | 28.30 | 228.11 | 0.94x |
| synth 8000x6000 | 256x192 | 0.25 | 43.44 | 42.89 | 57.78 | 49.85 | 225.34 | 1.01x |
| synth 8000x6000 | 512x384 | 0.89 | 51.65 | 44.64 | 58.16 | 48.22 | 227.62 | 1.16x |
| synth 8000x6000 | 1024x768 | 2.25 | 66.26 | 99.47* | 104.58 | 35.45 | 107.59 | 0.67x* |
| synth 8000x6000 | 1920x1440 | 5.29 | 89.86 | 49.69 | 57.15 | 43.49 | 105.04 | 1.81x |

\* The 48 MP rows were the noisiest: the three process rounds for FIR Box at 1024 px were
[107.2, 99.5, 44.9] ms while Qt smooth was [88.3, 65.6, 66.3] ms. Treat that cell as inconclusive;
the min-of-min cross-check below gives 1.34x. The 192 and 256 rows were consistent across rounds.

### Noise-robust cross-check and quality

Min-of-min timing (fastest iteration across three processes) and PSNR of FIR Box against
Qt Smooth on the full RGB output:

| Source | Target | Qt Smooth min ms | FIR Box min ms | Speedup | PSNR (dB) |
| --- | --- | ---: | ---: | ---: | ---: |
| demo | 192x128 | 2.52 | 2.07 | 1.22x | 47.47 |
| demo | 256x170 | 3.00 | 2.12 | 1.42x | 44.79 |
| demo | 512x341 | 4.18 | 2.55 | 1.64x | 41.10 |
| demo | 1024x682 | 7.95 | 3.81 | 2.09x | 35.94 |
| 12 MP | 192x144 | 11.57 | 10.51 | 1.10x | 51.10 |
| 12 MP | 256x192 | 12.10 | 10.64 | 1.14x | 50.35 |
| 12 MP | 512x384 | 14.78 | 11.16 | 1.32x | 45.65 |
| 12 MP | 1024x768 | 21.31 | 12.96 | 1.64x | 38.11 |
| 12 MP | 1920x1440 | 36.99 | 17.48 | 2.12x | 30.88 |
| 48 MP | 192x144 | 42.33 | 43.94 | 0.96x | 51.29 |
| 48 MP | 256x192 | 42.87 | 42.45 | 1.01x | 51.07 |
| 48 MP | 512x384 | 49.06 | 42.52 | 1.15x | 50.35 |
| 48 MP | 1024x768 | 59.80 | 44.76 | 1.34x | 45.66 |
| 48 MP | 1920x1440 | 81.85 | 49.34 | 1.66x | 39.10 |

Interpretation:

- At the product's actual 192x144 preview size, FIR Box is equal quality (PSNR 47-51 dB) but the
  speedup is 22% on the 2.2 MP demo (0.5 ms absolute), 10% on 12 MP, and negative on 48 MP.
  This does not change user-visible behaviour and does not clear a "material" bar.
- For 12 MP sources at >= 512 px, FIR Box is 32-112% faster with PSNR 46 dB (512 px) down to
  31 dB (1920 px). The speed is real, but there is no current call site at those sizes, and
  equal quality is only clearly established at 512 px.
- `BilinearInterp` is consistently the fastest but is a 2x2 interpolation; on a 48 MP -> 192 px
  downscale the sampling kernel is far too small (aliasing), so its speed is not usable as an
  equal-quality replacement.
- `Lanczos3` is slower than Qt Smooth in most cells (it uses a 6x6 kernel) and is not a speed win.
- Qt `FastTransformation` is much faster than everything else but is nearest-neighbour quality and
  was already rejected for previews.

Verdict: conditional performance win, not a win on the product's current thumbnail path.
Given ADR-0002's "no evidence, no Rust" and its warning against maintaining an unused module,
no resize module is shipped.

## Decode measurements (bonus)

Interleaved Qt/Rust decode, 3 process rounds x (3 warmup + 9 runs). The host contention made the
per-round medians unstable, so the table reports the fastest iteration across all rounds and the
round-median range. Decoded pixels were compared against Qt output.

| Input | Qt decode min ms | Rust decode min ms | Rust / Qt | Pixel PSNR vs Qt |
| --- | ---: | ---: | ---: | ---: |
| `assets/demo.jpg` 1800x1200 (2.2 MP) | 42.59 | 54.68 | 0.78x (Qt 1.28x faster) | 56.06 dB |
| `synth-6000x4000.jpg` 24 MP | 775.90 | 717.74 | 1.08x (Rust 8% faster) | 62.14 dB |
| `demo-1800x1200.png` 2.2 MP | 86.41 | 38.08 | 2.27x (Rust faster) | identical |

Round-to-round spread was large (for example Qt demo medians 44.5 / 158.6 / 92.5 ms); the
relative conclusion is stable only for the PNG case and for "Qt wins on the small JPEG".
JPEG decode is not a Rust win at the 20% bar.

## Licensing notes

Everything evaluated is permissive; no copyleft (GPL/AGPL) code is involved.

| Crate | Version | License | Role |
| --- | --- | --- | --- |
| `fast_image_resize` | 6.1.0 | MIT OR Apache-2.0 | Candidate C resize |
| `kamadak-exif` | 0.6.1 | BSD-2-Clause | Candidate A EXIF |
| `image` | 0.25.10 | MIT OR Apache-2.0 | Candidate B decode / benchmark jpeg+png |
| `num-traits` | 0.2.19 | MIT OR Apache-2.0 | fast_image_resize dependency |
| `thiserror` | 2.0.21 | MIT OR Apache-2.0 | fast_image_resize dependency |
| `cfg-if` | 1.0.5 | MIT OR Apache-2.0 | fast_image_resize dependency |
| `document-features` | 0.2.12 | MIT OR Apache-2.0 | fast_image_resize dependency (build) |
| `png` / `flate2` / `miniz_oxide` / `zune-jpeg` | as locked | MIT OR Apache-2.0 (miniz_oxide: MIT OR Zlib OR Apache-2.0) | `image` decode dependencies |
| `moxcms` / `pxfm` | as locked | BSD-3-Clause OR Apache-2.0 | `image` dependency |

The full scratch dependency graph was 44 packages according to `cargo metadata` (including the
local bench crate and duplicate major versions such as `syn` 2 and 3); every license is MIT,
Apache-2.0, BSD-2-Clause, BSD-3-Clause, Zlib, 0BSD or Unlicense, all permissive and compatible
with distribution. A shipped resize-only module would depend on `fast_image_resize` plus its small
transitive set (`cfg-if`, `num-traits`, `thiserror`, and build-only `document-features`), not on
`image`.

## Repository integration status

No changes to `native/CMakeLists.txt`, `native/cmake/NekoPicOptions.cmake`, `nekopic_io`,
`NekoPicRust.cmake`, `native/rust/nekopic-codecs/`, or any QML/controller file were made.
`NEKOPIC_WITH_RUST=OFF` is still the only supported configuration.

Verification performed:

- `cargo build --release` of the scratch benchmark crate: succeeded.
- `cargo test --release` of the scratch benchmark crate: 0 tests, result ok (it is a benchmark
  binary; no shipped Rust module exists to unit-test).
- CMake configure of `native/` with `-DNEKOPIC_WITH_RUST=OFF -DBUILD_TESTING=ON` in
  `/tmp/nekopic-build-off`: succeeded.
- C++ build of that tree (`cmake --build /tmp/nekopic-build-off -j 2`): 61/61 targets, exit 0.
- Qt baseline tests (`imageio_test`, `formatregistry_test`) run from that scratch build: both passed.
  The full C++ suite also passed 7/7 in 8.09 s (`ctest --test-dir /tmp/nekopic-build-off`).
