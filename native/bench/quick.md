# NekoPic pipeline benchmark

Mode: **quick**, one warmup + 5 measured runs per case.

- **CPU**: Intel(R) Core(TM) Ultra 7 258V (8 logical cores)
- **RAM**: 32313504 kB
- **OS**: Arch Linux
- **Qt**: runtime 6.12.0, built against 6.12.0
- **Compiler**: GCC 16.2.1
- **Build**: Release (NDEBUG)
- **Load average at start**: 2.68 5.92 5.07 1/1762 935552
- **Adjustment concurrency**: up to 8 independent cases at once (each case single-threaded; `--jobs 1` for serial)

> Shared-host caveat: these are wall-clock numbers from a general-purpose desktop. CPU frequency scaling, scheduler placement, file cache and background load change the results; treat medians as indicative and p95 as a tail warning, not as hardware guarantees. The adjustment matrix runs independent cases concurrently to keep the 48 MP sweep inside the runtime budget, so those values are upper bounds under all-core load. Run with `--jobs 1` on an otherwise idle machine for isolated latencies. Other suites run one case at a time.

Percentiles use linear interpolation between sorted samples; with five samples p95 is close to the maximum. Sizes are synthetic and deterministic (gradient + noise), generated in-process; only the demo decode reads from disk.

### 1. Adjustments (NekoPic::Adjustments::apply)

| Size | Format | Case | Runs | Min ms | Median ms | p95 ms | Max ms | Source MB | Result MB | Notes |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 0.5 MP | RGBA8888 | identity | 5 | 0.000 | 0.000 | 0.004 | 0.004 | 1.9 | 1.9 |  |
| 0.5 MP | RGBA8888 | exposure +1 | 5 | 47.04 | 49.01 | 55.53 | 56.88 | 1.9 | 3.8 |  |
| 0.5 MP | RGBA8888 | exposure +2 contrast | 5 | 47.44 | 49.87 | 55.25 | 56.37 | 1.9 | 3.8 |  |
| 0.5 MP | RGBA8888 | saturation -1 | 5 | 54.92 | 59.31 | 84.76 | 90.45 | 1.9 | 3.8 |  |
| 0.5 MP | RGBA8888 | mono filter | 5 | 38.25 | 38.75 | 43.23 | 44.19 | 1.9 | 3.8 |  |
| 0.5 MP | RGBA8888 | combined filter + intensity | 5 | 61.61 | 62.68 | 72.97 | 74.49 | 1.9 | 3.8 |  |
| 0.5 MP | RGBA64 | identity | 5 | 0.000 | 0.000 | 0.000 | 0.001 | 3.8 | 3.8 |  |
| 0.5 MP | RGBA64 | exposure +1 | 5 | 55.08 | 56.00 | 56.29 | 56.29 | 3.8 | 3.8 |  |
| 0.5 MP | RGBA64 | exposure +2 contrast | 5 | 58.75 | 61.10 | 63.25 | 63.71 | 3.8 | 3.8 |  |
| 0.5 MP | RGBA64 | saturation -1 | 5 | 51.26 | 56.08 | 57.89 | 58.28 | 3.8 | 3.8 |  |
| 0.5 MP | RGBA64 | mono filter | 5 | 38.01 | 39.31 | 39.80 | 39.86 | 3.8 | 3.8 |  |
| 0.5 MP | RGBA64 | combined filter + intensity | 5 | 57.82 | 59.25 | 59.72 | 59.83 | 3.8 | 3.8 |  |
| 2 MP | RGBA8888 | identity | 5 | 0.000 | 0.000 | 0.000 | 0.000 | 8.2 | 8.2 |  |
| 2 MP | RGBA8888 | exposure +1 | 5 | 184.7 | 186.0 | 192.7 | 193.0 | 8.2 | 16.5 |  |
| 2 MP | RGBA8888 | exposure +2 contrast | 5 | 253.1 | 258.3 | 272.2 | 275.0 | 8.2 | 16.5 |  |
| 2 MP | RGBA8888 | saturation -1 | 5 | 211.6 | 218.1 | 219.8 | 220.1 | 8.2 | 16.5 |  |
| 2 MP | RGBA8888 | mono filter | 5 | 172.3 | 175.8 | 182.5 | 182.6 | 8.2 | 16.5 |  |
| 2 MP | RGBA8888 | combined filter + intensity | 5 | 359.1 | 366.6 | 405.4 | 405.9 | 8.2 | 16.5 |  |
| 2 MP | RGBA64 | identity | 5 | 0.000 | 0.000 | 0.000 | 0.000 | 16.5 | 16.5 |  |
| 2 MP | RGBA64 | exposure +1 | 5 | 182.0 | 183.5 | 218.7 | 218.9 | 16.5 | 16.5 |  |
| 2 MP | RGBA64 | exposure +2 contrast | 5 | 246.1 | 249.2 | 285.4 | 291.7 | 16.5 | 16.5 |  |
| 2 MP | RGBA64 | saturation -1 | 5 | 181.5 | 183.1 | 189.9 | 191.4 | 16.5 | 16.5 |  |
| 2 MP | RGBA64 | mono filter | 5 | 165.0 | 167.6 | 171.4 | 171.6 | 16.5 | 16.5 |  |
| 2 MP | RGBA64 | combined filter + intensity | 5 | 229.2 | 230.8 | 233.6 | 233.7 | 16.5 | 16.5 |  |
| 8 MP | RGBA8888 | identity | 5 | 0.000 | 0.000 | 0.000 | 0.000 | 30.5 | 30.5 |  |
| 8 MP | RGBA8888 | exposure +1 | 5 | 640.4 | 642.8 | 665.1 | 667.1 | 30.5 | 61.0 |  |
| 8 MP | RGBA8888 | exposure +2 contrast | 5 | 670.4 | 756.2 | 760.9 | 761.1 | 30.5 | 61.0 |  |
| 8 MP | RGBA8888 | saturation -1 | 5 | 627.2 | 633.8 | 735.8 | 739.7 | 30.5 | 61.0 |  |
| 8 MP | RGBA8888 | mono filter | 5 | 674.3 | 708.3 | 789.6 | 806.7 | 30.5 | 61.0 |  |
| 8 MP | RGBA8888 | combined filter + intensity | 5 | 1150.0 | 1235.2 | 1320.6 | 1327.8 | 30.5 | 61.0 |  |
| 8 MP | RGBA64 | identity | 5 | 0.000 | 0.000 | 0.000 | 0.000 | 61.0 | 61.0 |  |
| 8 MP | RGBA64 | exposure +1 | 5 | 713.1 | 911.4 | 941.4 | 943.0 | 61.0 | 61.0 |  |
| 8 MP | RGBA64 | exposure +2 contrast | 5 | 794.3 | 998.7 | 1056.6 | 1056.9 | 61.0 | 61.0 |  |
| 8 MP | RGBA64 | saturation -1 | 5 | 623.2 | 697.1 | 749.4 | 758.2 | 61.0 | 61.0 |  |
| 8 MP | RGBA64 | mono filter | 5 | 416.9 | 472.5 | 543.4 | 554.0 | 61.0 | 61.0 |  |
| 8 MP | RGBA64 | combined filter + intensity | 5 | 1030.7 | 1123.8 | 1170.7 | 1177.7 | 61.0 | 61.0 |  |

### 2. Filter preview batch (192x144, six presets)

| Size | Format | Case | Runs | Min ms | Median ms | p95 ms | Max ms | Source MB | Result MB | Notes |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 0.5 MP | RGBA8888 | batch (downscale + 6 presets) | 5 | 16.24 | 19.14 | 19.79 | 19.94 | 1.9 | 0.6 | batch = smooth downscale to 192x144 + six presets; per-thumbnail median 3.191 ms |
| 2 MP | RGBA8888 | batch (downscale + 6 presets) | 5 | 16.20 | 17.80 | 19.06 | 19.20 | 8.2 | 0.6 | batch = smooth downscale to 192x128 + six presets; per-thumbnail median 2.967 ms |
| 8 MP | RGBA8888 | batch (downscale + 6 presets) | 5 | 23.68 | 24.27 | 25.00 | 25.08 | 30.5 | 0.6 | batch = smooth downscale to 192x144 + six presets; per-thumbnail median 4.046 ms |

### 3. Mosaic (12 MP, moderate area)

| Size | Format | Case | Runs | Min ms | Median ms | p95 ms | Max ms | Source MB | Result MB | Notes |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 12 MP | RGBA8888 | rectangle block 8 | 5 | 145.6 | 154.9 | 159.1 | 159.3 | 45.8 | 45.8 | ROI 1200x900 (9% of image) |
| 12 MP | RGBA8888 | rectangle block 32 | 5 | 140.0 | 148.0 | 161.5 | 163.2 | 45.8 | 45.8 | ROI 1200x900 (9% of image) |
| 12 MP | RGBA8888 | rectangle block 128 | 5 | 147.9 | 158.3 | 169.6 | 171.7 | 45.8 | 45.8 | ROI 1200x900 (9% of image) |
| 12 MP | RGBA8888 | stroke block 8 | 5 | 53.53 | 55.15 | 58.36 | 58.46 | 45.8 | 45.8 | 64 points, diameter 96, ROI approx 2200x1000 |
| 12 MP | RGBA8888 | stroke block 32 | 5 | 60.71 | 61.20 | 62.40 | 62.49 | 45.8 | 45.8 | 64 points, diameter 96, ROI approx 2200x1000 |
| 12 MP | RGBA8888 | stroke block 128 | 5 | 68.72 | 71.71 | 77.89 | 79.05 | 45.8 | 45.8 | 64 points, diameter 96, ROI approx 2200x1000 |
| 12 MP | RGBA64 | rectangle block 32 | 5 | 33.65 | 34.31 | 34.90 | 34.99 | 91.6 | 91.6 | ROI 1200x900 (9% of image) |
| 12 MP | RGBA64 | stroke block 32 | 5 | 30.44 | 31.29 | 31.61 | 31.67 | 91.6 | 91.6 | 64 points, diameter 96, ROI approx 2200x1000 |

### 4a. Interaction latency proxies

| Size | Format | Case | Runs | Min ms | Median ms | p95 ms | Max ms | Source MB | Result MB | Notes |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 0.5 MP | RGBA8888 | first preview 1600x1000 | 5 | 126.2 | 137.2 | 145.9 | 147.5 | 1.9 | 10.2 | downscale + apply; proposed display-scale proxy |
| 0.5 MP | RGBA8888 | exposure +2 contrast | 5 | 47.44 | 49.87 | 55.25 | 56.37 | 1.9 | 3.8 | full-size authoritative render, same parameters |
| 2 MP | RGBA8888 | first preview 1600x1000 | 5 | 139.9 | 143.9 | 157.2 | 160.2 | 8.2 | 11.4 | downscale + apply; proposed display-scale proxy |
| 2 MP | RGBA8888 | exposure +2 contrast | 5 | 253.1 | 258.3 | 272.2 | 275.0 | 8.2 | 16.5 | full-size authoritative render, same parameters |
| 8 MP | RGBA8888 | first preview 1600x1000 | 5 | 131.6 | 152.5 | 154.0 | 154.1 | 30.5 | 10.2 | downscale + apply; proposed display-scale proxy |
| 8 MP | RGBA8888 | exposure +2 contrast | 5 | 670.4 | 756.2 | 760.9 | 761.1 | 30.5 | 61.0 | full-size authoritative render, same parameters |
| 2 MP | RGBA8888 | QtConcurrent dispatch + result | 5 | 243.6 | 244.4 | 247.1 | 247.5 | 8.2 | 16.5 | thread handoff + event-loop delivery; excludes UI debounce |

### 5. GPU preview CPU mirror vs authoritative CPU

| Size | Format | Case | Runs | Min ms | Median ms | p95 ms | Max ms | Source MB | Result MB | Notes |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 2 MP | RGBA8888 -> RGBA64 | authoritative CPU apply | 5 | 227.1 | 228.2 | 235.1 | 236.4 | 7.9 | 15.8 | export/commit path |
| 2 MP | RGBA8888 | shader CPU mirror | 5 | 68.58 | 72.96 | 73.35 | 73.43 | 7.9 | 7.9 | CPU stand-in for the GPU shader; not used for export |
| 2 MP | RGBA64 | authoritative CPU apply | 5 | 225.3 | 237.9 | 240.6 | 241.1 | 15.8 | 15.8 | export/commit path |
| 2 MP | RGBA64 | shader CPU mirror | 5 | 72.49 | 72.93 | 73.15 | 73.19 | 15.8 | 15.8 | CPU stand-in for the GPU shader; not used for export |

### 6. Import/decode

| Size | Format | Case | Runs | Min ms | Median ms | p95 ms | Max ms | Source MB | Result MB | Notes |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 1800x1200 | QImageReader | bundled JPEG | 5 | 44.33 | 44.44 | 44.84 | 44.93 | 8.2 | 8.2 | warm file cache; 471 KiB file; cold disk not measured |

### Memory accounting (QImage::sizeInBytes)

Accounting model only, not process RSS. Base is the imported image; rendered is the authoritative RGBA64 result. Undo capacity uses the production 256 MiB history budget.

| Size | Source format | Base MB | Rendered MB | Undo snapshots retained | Accounted peak MB | Notes |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| 0.5 MP | RGBA8888 | 1.9 | 3.8 | 66 | 253.4 | history can retain 66 rendered snapshot(s) within 256 MiB |
| 0.5 MP | RGBA64 | 3.8 | 3.8 | 66 | 255.3 | history can retain 66 rendered snapshot(s) within 256 MiB |
| 2 MP | RGBA8888 | 8.2 | 16.5 | 15 | 255.4 | history can retain 15 rendered snapshot(s) within 256 MiB |
| 2 MP | RGBA64 | 16.5 | 16.5 | 14 | 247.2 | history can retain 14 rendered snapshot(s) within 256 MiB |
| 8 MP | RGBA8888 | 30.5 | 61.0 | 3 | 213.4 | history can retain 3 rendered snapshot(s) within 256 MiB |
| 8 MP | RGBA64 | 61.0 | 61.0 | 3 | 243.8 | history can retain 3 rendered snapshot(s) within 256 MiB |

CSV written to native/bench/quick-results.csv
JSON written to native/bench/quick-results.json

### Budget checks (advisory)

| Suite | Case | Size | p95 ms | Ceiling ms | Result | Rationale |
| --- | --- | --- | ---: | ---: | --- | --- |
| filter-previews | batch (downscale + 6 presets) | 2 MP | 19.06 | 60.00 | PASS | regression ceiling; product target <= 16 ms per batch |
| interaction | first preview 1600x1000 | 2 MP | 157.2 | 500.0 | PASS | regression ceiling; product target <= 33 ms on the GPU path |
| adjustments | exposure +1 | 2 MP | 192.7 | 800.0 | PASS | regression ceiling; product target <= 33 ms for an interactive preview |
| decode | bundled JPEG | 1800x1200 | 44.84 | 150.0 | PASS | regression ceiling; warm import target <= 100 ms |

4 budget check(s), 0 failure(s).

Completed 65 rows, 0 skipped; sink=450401251188420.
