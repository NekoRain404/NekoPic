# Contributing to NekoPic

NekoPic is a Linux-first desktop photo editor: **C++20 + Qt 6 for the engine and
Qt Quick/QML for the interface**. The H5 prototype is reference material only;
product work happens in `native/`.

## Before you start

Read, in order:

1. [`docs/architecture/overview.md`](docs/architecture/overview.md) — layers and thread contracts.
2. [`docs/architecture/module-map.md`](docs/architecture/module-map.md) — ownership and dependencies.
3. [`docs/repository-structure.md`](docs/repository-structure.md) — where files belong.
4. [`docs/development.md`](docs/development.md) — branch, build and test workflow.
5. [`docs/packaging.md`](docs/packaging.md) — release and packaging checklist.

## Build and verify

```sh
cmake -S native -B native/build -G Ninja -DCMAKE_BUILD_TYPE=Debug
cmake --build native/build -j2
ctest --test-dir native/build --output-on-failure

# one-shot full gate: configure, build, C++ tests, QML tests, whitespace
./scripts/check.sh native/build-check

# GPU/RHI QML path
QT_QPA_PLATFORM=offscreen QSG_RHI_BACKEND=opengl QT_QUICK_BACKEND=rhi \
  /usr/lib/qt6/bin/qmltestrunner -input native/qml/tests -silent

# sanitizers
./scripts/check-sanitizers.sh native/build-sanitize
```

A change is not complete until the relevant C++ tests, QML tests and
`git diff --check` pass. Performance-sensitive changes must also run the
benchmark (`native/build-release/bench_pipeline --quick --jobs 1`).

## Code organization

The dependency direction is one-way:

```text
core -> io / document / render -> platform -> app -> QML
```

- `core/` contains framework-light algorithms and must not depend on QML or UI.
- `document/` owns object/history state; `render/` owns preview math and GPU
  capability probes; `io/` owns decoding/encoding and format capabilities.
- `app/` is the Qt bridge (`DocumentController`, managers) and may use Qt Widgets
  only where already established; QML must not reach into implementation details.
- New QML components use the `Neko` prefix only for design-system primitives in
  `qml/UI`; feature components live next to their feature folder and use
  `Theme`/`Motion` tokens, `objectName`s and accessibility names.

## File size budget

Large files are hard to review, test and merge. Keep source files small and split
by responsibility, not mechanically at line boundaries.

| Kind | Target | Review hard stop | Notes |
| --- | ---: | ---: | --- |
| C++ `.cpp` / `.h` | ≤ 600 lines | 800 lines / 30 KiB | Move stages/helpers into sibling files and an internal header. |
| QML `.qml` | ≤ 600 lines | 800 lines / 28 KiB | Extract a feature page, panel or shell component. |
| QML/C++ tests | no fixed target | keep per-feature | Split one test file per feature; avoid mega-window fixtures. |
| Generated/prototype assets | excluded | — | `prototype/h5/`, build dirs and artifacts are not product sources. |

If a file must exceed the hard stop, document the reason in the commit and add a
split task to the relevant roadmap entry. Do not commit build outputs, generated
`.qsb` copies outside the build, editor state or local screenshots.

## Naming and UI rules

- C++: `.clang-format`, 4 spaces, 100 columns, `NekoPic` namespace for engine code.
- QML: 4 spaces, imports ordered, no hard-coded colors/spacings when a `Theme`
  or `Motion` token exists. Use `qsTr()` for user-visible strings; settings-page
  code may use the existing `_tr()` pattern.
- Every interactive control needs an `objectName` and an accessible name.
- Never block the GUI thread on image processing; follow the existing
  snapshot/worker/`QFutureWatcher`/GUI-commit contract.
- Exactness first: previews may approximate, committed pixels must match the
  authoritative CPU path.

## Commits and branches

- Conventional Commits: `feat(scope): ...`, `fix(scope): ...`, `refactor(scope): ...`,
  `docs: ...`, `test(scope): ...`, `build: ...`, `perf(scope): ...`.
- One concern per commit. Include tests and docs with the behavior change.
- Feature work branches from `develop`; use an isolated worktree for parallel
  work. Do not push or rewrite shared history unless the owner asks.
- Keep `develop` green: merge only after the full gate passes.

## Release and packaging

- Version lives in `native/CMakeLists.txt` (`project(... VERSION ...)`).
- Packaging metadata lives in `packaging/`; install rules and CPack live in
  `native/CMakeLists.txt`. See [`docs/packaging.md`](docs/packaging.md).
- The project license is **not yet chosen**. Do not add a license or claim one
  in packages until the owner decides; the AppStream metadata uses
  `LicenseRef-proprietary` as a placeholder and must be updated before a public
  release.
- A release requires: clean Release build, C++/QML/RHI tests, sanitizer run,
  `desktop-file-validate`, `appstreamcli validate`, install-tree inspection and
  an offscreen smoke screenshot.
