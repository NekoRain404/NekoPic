# Changelog

All notable changes to NekoPic are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- CI workflow for configure/build/C++/QML tests and an ASan/UBSan job.
- Window icon embedded in the executable for X11/AppImage.
- Japanese and German desktop-entry names, comments and keywords.
- `CHANGELOG.md` and repository/engineering standards.

### Changed

- AppImage now bundles QML and Wayland platform plugins and defaults to
  XWayland for reliable first-frame presentation; native Wayland is available
  with `NEKOPIC_APPIMAGE_PLATFORM=wayland`.
- `colorpipeline.cpp` split into six stage units; settings and shell pages split
  into `qml/settings/*` and `qml/shell/*`.

## [0.1.0] — 2026-11-05

First development release. Not yet recommended for irreplaceable photos.

### Added

- Native Qt 6 / C++20 / Qt Quick editor with `core → io/document/render →
  platform → app → QML` layering.
- Colour workspace: basic tone and white balance, eight-band HSL, five-point
  RGB/R/G/B curves, colour grading, detail/effects, sampled histogram and
  auto-enhance.
- Twelve filter presets plus Original, with categories, search, favourites and
  intensity; thumbnails render from the current image.
- GPU interactive preview for exposure, brightness, contrast, saturation,
  highlights, shadows, whites, blacks, temperature, tint and vibrance.
- Display-resolution proxy previews for advanced CPU adjustments and an
  adjusted-base cache for fast object edits.
- Document objects: text (styled, re-editable), shapes, polygons, brush strokes
  with opacity/softness, multi-select, layer panel, alignment, visibility, lock,
  stacking order, live drag with magnetic guides.
- Crop, rotate, flip, image resize, canvas resize, mosaic and blur.
- Undo/redo with a 256 MiB unique-image budget; crash-recovery snapshots with
  startup restore/discard and a flattened-image limitation.
- Seven theme modes (system, light, dark, midnight, warm paper, graphite, high
  contrast) driven by one token system.
- System font catalog (784 families on the development host) with a searchable
  text font picker.
- English, Simplified Chinese, Japanese and German UI catalogues (755 messages
  per translated locale).
- Broad Qt codec support through a capability registry; export quality, JPEG
  background, clipboard output, recent files, drag-and-drop and command palette.
- Packaging: CMake install rules, CPack TGZ/DEB/RPM, desktop entry, AppStream
  metadata, 16–512 px hicolor icons and a scalable SVG, AppDir/AppImage build,
  and an experimental Flatpak manifest.

### Known limitations

- No project file format; saving writes the merged image.
- Recovery snapshots are flattened; objects cannot be re-edited after restore.
- The project license is not yet chosen; package metadata uses
  `LicenseRef-proprietary` as a placeholder.
- AppStream screenshots and a homepage URL are still missing.
- RPM/DEB dependency names are not verified on Fedora/Debian target machines.
- `Main.qml` remains a large composition root; further shell extraction is
  tracked.
- Full ICC colour management, EXIF-preserving export, brush spacing/pressure
  and GPU coverage for the remaining CPU-only stages are not implemented.
