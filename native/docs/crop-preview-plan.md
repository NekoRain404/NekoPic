# Crop and live filter previews

This increment implements two requirements from the approved desktop editor direction. It does not redefine the full application milestone.

## Shared constraints

- C++20, Qt 6.5+, Qt Quick; retain native dialogs, existing themes and translations.
- Workers operate on immutable QImage snapshots; GUI QObject state changes remain on the GUI thread.
- Preserve unrelated uncommitted changes. No agent commits, recursive agents, or shared build directories.
- Write focused behavior tests and observe failure before implementation. Keep modules focused and comments about intent or coordinate contracts.
- Parent owns Main.qml, CMakeLists.txt, translations, README and integration tests. Worker ownership below is exclusive.

## Task 1: Crop backend

Own `src/app/documentcontroller_geometry.cpp`, the minimal crop API addition in `documentcontroller.h`, and `tests/tst_crop.cpp`.

Expose `Q_INVOKABLE void cropImage(const QRectF &area)` on DocumentController. Coordinates describe continuous image pixel edges. Reject nonfinite / extreme coordinates, no image and busy calls. Normalize reversed rectangles, clip to base image, align outward to integer pixel boundaries, clip again. Empty and full-image crops are no-ops. Asynchronously copy both rendered image and base image into the same rectangle; preserve format, channel/alpha bits, profile, resolution and adjustment/filter parameters. A successful crop creates one undo step through applyEdit, updates dimensions/dirty state, and preserves save/redo semantics. Never resample or rerender. Handle failures through existing errorMessage and busy state. Tests cover clipped/reversed/fractional rectangles, one-pixel crop, invalid/no-op/busy, undo/redo, saved-state return, existing parameters and 16-bit/float metadata/pixels. Parent wires tests to CMake.

## Task 2: Crop QML

Own `qml/CropOverlay.qml`, `qml/CropPanel.qml`, `qml/EditorCanvas.qml`, `qml/tests/tst_crop_overlay.qml`, `qml/tests/tst_crop_panel.qml`. Parent integrates Main.

CropOverlay lives over the displayed image. Public properties: `active`, `inputEnabled`, `imageWidth`, `imageHeight`, `aspectRatio` (0=free), `selection` (rect in image pixels), `visibleRect` in local display pixels. Public function `resetSelection()`. Signals `applyRequested(rect area)`, `cancelled()`. Start full image, or largest centered rectangle matching ratio. Draw a bounded dimmed overlay with rule-of-thirds guides and eight handles. Drag to create/move/resize selection; clamp all changes to image bounds. Escape cancels and Enter requests apply. Middle button and wheel pass through to the existing pan/zoom. Viewport-backed rendering only, no image-sized raster buffer. Changing image dimensions or activating anew resets selection. Fixed ratios remain fixed during creation/resizing; no inversion or zero-area commits.

EditorCanvas adds `cropActive`, `cropAspectRatio`; exposes read-only `cropSelection` bound to overlay selection; function `resetCropSelection()`; signals `cropApplyRequested(rect area)` and `cropCancelled()`. Bind enabled and geometry exactly like mosaic overlay. Existing mosaic/zoom tests must remain passing.

CropPanel follows existing theme/density. Properties: `theme`, `aspectRatio` (0=free), `imageAspectRatio`, `selectionWidth`, `selectionHeight`, `canApply`. Signals `applyRequested()`, `cancelRequested()`, `resetRequested()`. Presets Free, Original, 1:1, 4:3, 3:2, 16:9; portrait/landscape swap; selection dimensions; Apply/Cancel/Reset. Translatable strings. Tests verify actual gestures, ratio/bounds, coordinate mapping across zoom/pan, no accidental middle/wheel capture, keyboard confirm/cancel, disabled states and size-changing reset.

## Task 3: Current-photo filter previews

Own new focused files under `src/app/filterpreview*`, registration in `src/app/main.cpp`, filter tile changes in `qml/Inspector.qml`, dedicated C++/QML preview tests. Parent supplies any needed Main bindings and CMake.

Use current DocumentController baseImage and adjustmentParameters snapshots, overriding filter preset per tile at full intensity. Original means adjustments without filter. Include current crop/mosaic changes. Asynchronously generate six previews bounded to 192x144 logical pixels; handle stale results, document close/open, worker failure and QObject shutdown safely; bound cache and do not run full-size effects six times. Work from a small downsample first. Expose a `filterPreviews` QObject to QML with documented URL/ready/revision properties and a registered image provider. Inspector optional `previewRevision` and `previewsAvailable` properties supplied by parent, using provider URLs as documented by worker. Retain readable labels/selection and swatch fallback when unavailable. Previews must reflect source/adjustments rather than the already-filtered image; avoid rebuilding solely for intensity/preset changes if possible. Tests verify real pixel differences, original/selected-filter separation, source changes, dimensions/cache bounds and stale/shutdown handling. No controller edits. Report limitations (e.g. ICC display behavior) accurately.

## Parent integration and verification

Wire CMake sources/tests, Main tool activation, menu/toolbar action, panel, confirmation/cancel, busy gating, previews and test stubs. Translate strings, document precise behavior and remaining gaps. Run full C++ and QML suites, sanitizer checks, diff checks and real-display verification where feasible. Independent review resolves correctness findings before declaring this increment done.
