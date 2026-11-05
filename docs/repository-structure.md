# Repository structure

Status: 2026-11-05. This is the reference tree for new work. Build directories,
`.claude/worktrees/`, `artifacts/` and other generated files are local-only and
must not be committed.

```text
NekoPic/
├── README.md                  Product overview and quick start
├── CONTRIBUTING.md            Engineering rules, file-size budget, gate
├── HANDOFF.md                 Long-form handoff and decision log
├── assets/                    Shared demo photo (native + H5 reference)
├── docs/                      Architecture, ADRs, parity/audits, release docs
│   ├── architecture/          Overview, module map, object model, formats
│   ├── adr/                   Architecture decision records
│   ├── development.md         Branch/build/test workflow
│   ├── repository-structure.md
│   ├── packaging.md           Packaging and release checklist (packaging workstream)
│   ├── performance*.md        Benchmarks, budgets, audit results
│   └── h5-*.md                H5 parity and UI audit
├── packaging/                 desktop file, AppStream metainfo, SVG icon,
│                              Flatpak/AppImage notes (packaging workstream)
├── prototype/
│   ├── README.md              Prototype usage
│   └── h5/                    Original HTML/CSS/JS reference (not shipped)
│       └── assets -> ../../assets
├── scripts/                   check.sh, check-sanitizers.sh, bench.sh,
│                              screenshot.sh, package.sh
└── native/
    ├── CMakeLists.txt         Targets, QML/shaders resources, install/CPack
    ├── cmake/                 Optional feature fragments and options
    ├── src/
    │   ├── core/              Algorithms: colour pipeline, filters, mosaic,
    │   │                      histogram, auto-enhance, row-parallel helpers
    │   ├── io/                ImageIO, format capability registry
    │   ├── document/          Object model, layer, history
    │   ├── render/            Preview math, GPU capability probes
    │   ├── platform/          Clipboard, recent files
    │   └── app/               DocumentController and Qt app services
    ├── qml/
    │   ├── UI/                Design-system primitives (Neko*)
    │   ├── shell/             Top bar, tool rail, status bar (split target)
    │   ├── effects/           GPU adjustment preview wrapper
    │   ├── panels/            Brush/Text/Shape/Filters/Mosaic properties
    │   ├── inspector/         Colour workspace tabs and controls
    │   ├── overlays/          Crop, mosaic, text, shape, brush, selection
    │   ├── objects/           Layer panel
    │   ├── settings/          Settings pages (split target)
    │   ├── dialogs/           Export, resize, canvas, shortcuts, settings shell
    │   └── tests/             QML tests and shader fixtures
    ├── tests/                 C++ tests and benchmark harness
    ├── shaders/               Runtime shader sources compiled to .qsb
    ├── i18n/                  Qt Linguist source catalogues
    └── rust/                  Optional Rust spike + benchmark evidence
```

## Placement rules

- A new image algorithm goes in `src/core/` with a focused header and tests in
  `native/tests/`; it must not depend on QML.
- A new document command goes in the matching `documentcontroller_*.cpp` and
  keeps the history/worker contract in `documentcontroller.h`.
- A new tool gets one QML panel/overlay pair and one QML test file; shared
  controls belong in `qml/UI`, not duplicated per tool.
- Settings categories belong in `qml/settings/`; `SettingsDialog.qml` should stay
  the shell and persistence adapter.
- Shell chrome belongs in `qml/shell/`; `Main.qml` should be composition and
  action wiring, not a mega-view.
- Packaging-only files belong in `packaging/`; build/install logic stays in
  `native/CMakeLists.txt` and `native/cmake/`.
- H5-only changes stay in `prototype/h5/` and are never required for the native
  build.

## Size and split policy

The short version is in `CONTRIBUTING.md`: target ≤ 600 lines per C++/QML source
file, review hard stop at 800 lines / ~30 KiB. Split by responsibility (stage,
page, panel, tool) with tests preserved.

Already split: `src/core/colorpipeline.cpp` into six stage units (largest 436
lines), `SettingsDialog.qml` into `qml/settings/*` pages (shell 542 lines), and
`Main.qml` into `qml/shell/*` (tool rail, top bar, status bar, info panel).
`Main.qml` remains the composition root at ~1300 lines; do not add new feature
logic there—extract a shell component or a page, and keep reducing it toward the
800-line review stop.

## Generated files

- `native/build*/`, `build-*/`, `CMakeFiles/`, `CMakeCache.txt` — ignored.
- `artifacts/` — local screenshots and benchmark output; ignored.
- `.claude/worktrees/` — agent worktrees; ignored.
- `native/qml/tests/fixtures/*.qsb` — checked in only as a test fixture; runtime
  shaders are compiled by `qt_add_shaders` into the build.
