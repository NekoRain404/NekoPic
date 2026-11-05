# Release screenshots

These images are source assets for the AppStream metadata and release notes.
They are captured offscreen from `assets/demo.jpg` at 1440×900 with the dark
theme, so they do not depend on a live compositor.

| File | Caption |
| --- | --- |
| `main-dark.png` | Colour workspace with the adjustment inspector and histogram |
| `filters-dark.png` | Filter library with live thumbnails from the current photo |
| `settings-dark.png` | The two-column preferences page (appearance category) |

Before a public release, upload these to a stable HTTPS location (release
assets or the project website) and replace the commented URLs in
`packaging/nekopic.metainfo.xml`. AppStream does not accept repository-relative
paths. Regenerate with:

```sh
QT_QPA_PLATFORM=offscreen native/build-integration/nekopic assets/demo.jpg \
    --screenshot packaging/screenshots/main-dark.png
QT_QPA_PLATFORM=offscreen native/build-integration/nekopic assets/demo.jpg \
    --tool filters --screenshot packaging/screenshots/filters-dark.png
# settings needs reduceMotion=true so the modal is fully expanded at capture time
XDG_CONFIG_HOME=/tmp/nekopic-settings-shot QT_QPA_PLATFORM=offscreen \
    native/build-integration/nekopic assets/demo.jpg --settings \
    --screenshot packaging/screenshots/settings-dark.png
```

The screenshots are intentionally excluded from the installed package; they are
release-note assets, not runtime files.
