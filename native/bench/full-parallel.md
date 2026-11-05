# NekoPic pipeline benchmark

Mode: **full**, one warmup + 5 measured runs per case.

- **CPU**: Intel(R) Core(TM) Ultra 7 258V (8 logical cores)
- **RAM**: 32313504 kB
- **OS**: Arch Linux
- **Qt**: runtime 6.12.0, built against 6.12.0
- **Compiler**: GCC 16.2.1
- **Build**: Release (NDEBUG)
- **Load average at start**: 3.90 3.78 2.75 3/1792 930466
<!-- CPU/RAM lines corrected after the harness /proc parsing fix; timing rows are unchanged. -->
- **Adjustment concurrency**: up to 8 independent cases at once (each case single-threaded; `--jobs 1` for serial)

> Shared-host caveat: these are wall-clock numbers from a general-purpose desktop. CPU frequency scaling, scheduler placement, file cache and background load change the results; treat medians as indicative and p95 as a tail warning, not as hardware guarantees. The adjustment matrix runs independent cases concurrently to keep the 48 MP sweep inside the runtime budget, so those values are upper bounds under all-core load. Run with `--jobs 1` on an otherwise idle machine for isolated latencies. Other suites run one case at a time.

Percentiles use linear interpolation between sorted samples; with five samples p95 is close to the maximum. Sizes are synthetic and deterministic (gradient + noise), generated in-process; only the demo decode reads from disk.

### 1. Adjustments (NekoPic::Adjustments::apply)

| Size | Format | Case | Runs | Min ms | Median ms | p95 ms | Max ms | Source MB | Result MB | Notes |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 2 MP | RGBA8888 | identity | 5 | 0.000 | 0.000 | 0.002 | 0.003 | 7.9 | 7.9 |  |
| 2 MP | RGBA8888 | exposure +1 | 5 | 234.4 | 248.1 | 461.2 | 496.4 | 7.9 | 15.8 |  |
| 2 MP | RGBA8888 | exposure +2 contrast | 5 | 238.6 | 549.1 | 577.5 | 583.7 | 7.9 | 15.8 |  |
| 2 MP | RGBA8888 | saturation -1 | 5 | 283.5 | 400.8 | 553.3 | 563.2 | 7.9 | 15.8 |  |
| 2 MP | RGBA8888 | mono filter | 5 | 161.7 | 196.6 | 208.6 | 208.7 | 7.9 | 15.8 |  |
| 2 MP | RGBA8888 | combined filter + intensity | 5 | 285.0 | 327.1 | 421.2 | 424.4 | 7.9 | 15.8 |  |
| 2 MP | RGBA64 | identity | 5 | 0.000 | 0.000 | 0.004 | 0.005 | 15.8 | 15.8 |  |
| 2 MP | RGBA64 | exposure +1 | 5 | 206.5 | 211.8 | 248.1 | 250.5 | 15.8 | 15.8 |  |
| 2 MP | RGBA64 | exposure +2 contrast | 5 | 339.4 | 490.6 | 522.8 | 527.3 | 15.8 | 15.8 |  |
| 2 MP | RGBA64 | saturation -1 | 5 | 273.8 | 495.4 | 530.8 | 532.5 | 15.8 | 15.8 |  |
| 2 MP | RGBA64 | mono filter | 5 | 159.9 | 167.8 | 179.6 | 182.2 | 15.8 | 15.8 |  |
| 2 MP | RGBA64 | combined filter + intensity | 5 | 280.7 | 341.1 | 544.4 | 592.6 | 15.8 | 15.8 |  |
| 12 MP | RGBA8888 | identity | 5 | 0.000 | 0.000 | 0.000 | 0.000 | 45.8 | 45.8 |  |
| 12 MP | RGBA8888 | exposure +1 | 5 | 1398.1 | 1758.9 | 1833.6 | 1834.1 | 45.8 | 91.6 |  |
| 12 MP | RGBA8888 | exposure +2 contrast | 5 | 1619.7 | 2248.6 | 2814.5 | 2952.3 | 45.8 | 91.6 |  |
| 12 MP | RGBA8888 | saturation -1 | 5 | 1403.6 | 1646.3 | 2055.1 | 2071.4 | 45.8 | 91.6 |  |
| 12 MP | RGBA8888 | mono filter | 5 | 1176.6 | 1358.3 | 1502.0 | 1508.3 | 45.8 | 91.6 |  |
| 12 MP | RGBA8888 | combined filter + intensity | 5 | 1597.1 | 2385.4 | 3050.0 | 3163.5 | 45.8 | 91.6 |  |
| 12 MP | RGBA64 | identity | 5 | 0.000 | 0.000 | 0.000 | 0.000 | 91.6 | 91.6 |  |
| 12 MP | RGBA64 | exposure +1 | 5 | 1322.9 | 1375.0 | 1831.7 | 1873.1 | 91.6 | 91.6 |  |
| 12 MP | RGBA64 | exposure +2 contrast | 5 | 1470.6 | 1725.2 | 1924.8 | 1932.0 | 91.6 | 91.6 |  |
| 12 MP | RGBA64 | saturation -1 | 5 | 1066.2 | 1911.1 | 1935.9 | 1939.6 | 91.6 | 91.6 |  |
| 12 MP | RGBA64 | mono filter | 5 | 963.2 | 1384.2 | 2400.6 | 2601.9 | 91.6 | 91.6 |  |
| 12 MP | RGBA64 | combined filter + intensity | 5 | 1624.0 | 1693.6 | 2101.9 | 2131.1 | 91.6 | 91.6 |  |
| 48 MP | RGBA8888 | identity | 5 | 0.000 | 0.000 | 0.000 | 0.000 | 183.1 | 183.1 |  |
| 48 MP | RGBA8888 | exposure +1 | 5 | 6515.3 | 7898.0 | 8699.7 | 8699.9 | 183.1 | 366.2 |  |
| 48 MP | RGBA8888 | exposure +2 contrast | 5 | 6578.9 | 8264.5 | 9829.7 | 10087.7 | 183.1 | 366.2 |  |
| 48 MP | RGBA8888 | saturation -1 | 5 | 5863.9 | 7519.5 | 8583.1 | 8822.4 | 183.1 | 366.2 |  |
| 48 MP | RGBA8888 | mono filter | 5 | 4560.2 | 4984.5 | 6415.2 | 6740.6 | 183.1 | 366.2 |  |
| 48 MP | RGBA8888 | combined filter + intensity | 5 | 7352.0 | 9744.5 | 11223.1 | 11282.2 | 183.1 | 366.2 |  |
| 48 MP | RGBA64 | identity | 5 | 0.000 | 0.000 | 0.000 | 0.000 | 366.2 | 366.2 |  |
| 48 MP | RGBA64 | exposure +1 | 5 | 6595.3 | 7487.6 | 8298.3 | 8323.8 | 366.2 | 366.2 |  |
| 48 MP | RGBA64 | exposure +2 contrast | 5 | 5805.3 | 7308.9 | 8743.1 | 9098.4 | 366.2 | 366.2 |  |
| 48 MP | RGBA64 | saturation -1 | 5 | 4839.6 | 7500.2 | 8319.5 | 8364.0 | 366.2 | 366.2 |  |
| 48 MP | RGBA64 | mono filter | 5 | 3749.5 | 4138.7 | 5723.4 | 5938.4 | 366.2 | 366.2 |  |
| 48 MP | RGBA64 | combined filter + intensity | 5 | 6402.1 | 7454.7 | 7737.0 | 7803.3 | 366.2 | 366.2 |  |

### 2. Filter preview batch (192x144, six presets)

| Size | Format | Case | Runs | Min ms | Median ms | p95 ms | Max ms | Source MB | Result MB | Notes |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 2 MP | RGBA8888 | batch (downscale + 6 presets) | 5 | 15.85 | 16.64 | 21.05 | 22.11 | 7.9 | 0.5 | batch = smooth downscale to 192x108 + six presets; per-thumbnail median 2.773 ms |
| 12 MP | RGBA8888 | batch (downscale + 6 presets) | 5 | 25.27 | 26.65 | 30.15 | 30.70 | 45.8 | 0.6 | batch = smooth downscale to 192x144 + six presets; per-thumbnail median 4.442 ms |
| 48 MP | RGBA8888 | batch (downscale + 6 presets) | 5 | 55.56 | 57.40 | 66.61 | 67.84 | 183.1 | 0.6 | batch = smooth downscale to 192x144 + six presets; per-thumbnail median 9.567 ms |

### 3. Mosaic (12 MP, moderate area)

| Size | Format | Case | Runs | Min ms | Median ms | p95 ms | Max ms | Source MB | Result MB | Notes |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 12 MP | RGBA8888 | rectangle block 8 | 5 | 157.3 | 160.4 | 160.9 | 161.0 | 45.8 | 45.8 | ROI 1200x900 (9% of image) |
| 12 MP | RGBA8888 | rectangle block 32 | 5 | 161.9 | 164.1 | 164.3 | 164.3 | 45.8 | 45.8 | ROI 1200x900 (9% of image) |
| 12 MP | RGBA8888 | rectangle block 128 | 5 | 175.7 | 178.9 | 180.9 | 181.4 | 45.8 | 45.8 | ROI 1200x900 (9% of image) |
| 12 MP | RGBA8888 | stroke block 8 | 5 | 64.85 | 65.33 | 65.94 | 65.98 | 45.8 | 45.8 | 64 points, diameter 96, ROI approx 2200x1000 |
| 12 MP | RGBA8888 | stroke block 32 | 5 | 61.78 | 63.93 | 64.25 | 64.28 | 45.8 | 45.8 | 64 points, diameter 96, ROI approx 2200x1000 |
| 12 MP | RGBA8888 | stroke block 128 | 5 | 77.82 | 80.45 | 80.76 | 80.79 | 45.8 | 45.8 | 64 points, diameter 96, ROI approx 2200x1000 |
| 12 MP | RGBA64 | rectangle block 32 | 5 | 39.24 | 39.54 | 39.79 | 39.83 | 91.6 | 91.6 | ROI 1200x900 (9% of image) |
| 12 MP | RGBA64 | stroke block 32 | 5 | 33.56 | 33.65 | 34.46 | 34.52 | 91.6 | 91.6 | 64 points, diameter 96, ROI approx 2200x1000 |

### 4a. Interaction latency proxies

| Size | Format | Case | Runs | Min ms | Median ms | p95 ms | Max ms | Source MB | Result MB | Notes |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 2 MP | RGBA8888 | first preview 1600x1000 | 5 | 163.9 | 207.1 | 329.6 | 357.4 | 7.9 | 11.0 | downscale + apply; proposed display-scale proxy |
| 2 MP | RGBA8888 | exposure +2 contrast | 5 | 238.6 | 549.1 | 577.5 | 583.7 | 7.9 | 15.8 | full-size authoritative render, same parameters |
| 12 MP | RGBA8888 | first preview 1600x1000 | 5 | 303.4 | 382.4 | 397.4 | 397.8 | 45.8 | 10.2 | downscale + apply; proposed display-scale proxy |
| 12 MP | RGBA8888 | exposure +2 contrast | 5 | 1619.7 | 2248.6 | 2814.5 | 2952.3 | 45.8 | 91.6 | full-size authoritative render, same parameters |
| 48 MP | RGBA8888 | first preview 1600x1000 | 5 | 415.2 | 512.9 | 668.8 | 696.0 | 183.1 | 10.2 | downscale + apply; proposed display-scale proxy |
| 48 MP | RGBA8888 | exposure +2 contrast | 5 | 6578.9 | 8264.5 | 9829.7 | 10087.7 | 183.1 | 366.2 | full-size authoritative render, same parameters |
| 12 MP | RGBA8888 | QtConcurrent dispatch + result | 5 | 1693.8 | 1738.6 | 3117.7 | 3143.9 | 45.8 | 91.6 | thread handoff + event-loop delivery; excludes UI debounce |

### 5. GPU preview CPU mirror vs authoritative CPU

| Size | Format | Case | Runs | Min ms | Median ms | p95 ms | Max ms | Source MB | Result MB | Notes |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 2 MP | RGBA8888 -> RGBA64 | authoritative CPU apply | 5 | 170.4 | 175.5 | 179.8 | 180.8 | 7.9 | 15.8 | export/commit path |
| 2 MP | RGBA8888 | shader CPU mirror | 5 | 44.61 | 44.76 | 48.62 | 49.35 | 7.9 | 7.9 | CPU stand-in for the GPU shader; not used for export |
| 2 MP | RGBA64 | authoritative CPU apply | 5 | 225.9 | 226.1 | 228.5 | 228.9 | 15.8 | 15.8 | export/commit path |
| 2 MP | RGBA64 | shader CPU mirror | 5 | 72.37 | 72.53 | 72.94 | 72.96 | 15.8 | 15.8 | CPU stand-in for the GPU shader; not used for export |

### 6. Import/decode

| Size | Format | Case | Runs | Min ms | Median ms | p95 ms | Max ms | Source MB | Result MB | Notes |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 1800x1200 | QImageReader | bundled JPEG | 5 | 44.19 | 44.64 | 45.06 | 45.13 | 8.2 | 8.2 | warm file cache; 471 KiB file; cold disk not measured |

### Memory accounting (QImage::sizeInBytes)

Accounting model only, not process RSS. Base is the imported image; rendered is the authoritative RGBA64 result. Undo capacity uses the production 256 MiB history budget.

| Size | Source format | Base MB | Rendered MB | Undo snapshots retained | Accounted peak MB | Notes |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| 2 MP | RGBA8888 | 7.9 | 15.8 | 15 | 245.2 | history can retain 15 rendered snapshot(s) within 256 MiB |
| 2 MP | RGBA64 | 15.8 | 15.8 | 15 | 253.1 | history can retain 15 rendered snapshot(s) within 256 MiB |
| 12 MP | RGBA8888 | 45.8 | 91.6 | 2 | 228.9 | history can retain 2 rendered snapshot(s) within 256 MiB |
| 12 MP | RGBA64 | 91.6 | 91.6 | 1 | 183.1 | history can retain 1 rendered snapshot(s) within 256 MiB |
| 48 MP | RGBA8888 | 183.1 | 366.2 | 0 | 549.3 | base + one render already exceeds the history budget; no undo snapshot retained |
| 48 MP | RGBA64 | 366.2 | 366.2 | 0 | 732.4 | base + one render already exceeds the history budget; no undo snapshot retained |

Completed 65 rows, 0 skipped; sink=452775157837668.
