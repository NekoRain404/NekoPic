import QtQuick

/*!
    CommandCatalog — the command-palette catalogue and executor.

    The shell supplies its shared Action map plus the few document flags the
    palette exposes. Commands that map one-to-one onto an Action trigger it;
    operations with distinct palette behaviour are reported as signals so the
    shell keeps ownership of editor and window state.

    Static labels use the original "Main" translation context, so extracting
    the catalogue does not change localisation.
*/
QtObject {
    id: catalog

    property var actions: ({})
    property bool busy: false
    property bool hasImage: false
    property bool languageAvailable: false
    property var recentEntries: []

    signal undoRequested()
    signal redoRequested()
    signal autoEnhanceRequested()
    signal toggleDarkThemeRequested()
    signal toggleFollowSystemThemeRequested()
    signal toggleReduceMotionRequested()
    signal languageSelected(string id)
    signal recentRequested(url url)

    readonly property var commands: [
        { title: actions.open.text, detail: qsTranslate("Main", "File"),
          shortcut: "Ctrl+O", enabled: actions.open.enabled,
          run: function() { actions.open.trigger() } },
        { title: actions.save.text, detail: qsTranslate("Main", "File"),
          shortcut: "Ctrl+S", enabled: actions.save.enabled,
          run: function() { actions.save.trigger() } },
        { title: actions.saveAs.text, detail: qsTranslate("Main", "File"),
          shortcut: "Ctrl+Shift+S", enabled: actions.saveAs.enabled,
          run: function() { actions.saveAs.trigger() } },
        { title: actions.undo.text, detail: qsTranslate("Main", "Edit"),
          shortcut: "Ctrl+Z", enabled: actions.undo.enabled,
          run: function() { catalog.undoRequested() } },
        { title: actions.redo.text, detail: qsTranslate("Main", "Edit"),
          shortcut: "Ctrl+Shift+Z", enabled: actions.redo.enabled,
          run: function() { catalog.redoRequested() } },
        { title: actions.copy.text, detail: qsTranslate("Main", "Edit"),
          shortcut: "Ctrl+Shift+C", enabled: actions.copy.enabled,
          run: function() { actions.copy.trigger() } },
        { title: actions.rotateRight.text, detail: qsTranslate("Main", "Image"),
          enabled: actions.rotateRight.enabled,
          run: function() { actions.rotateRight.trigger() } },
        { title: actions.rotateLeft.text, detail: qsTranslate("Main", "Image"),
          enabled: actions.rotateLeft.enabled,
          run: function() { actions.rotateLeft.trigger() } },
        { title: actions.flipHorizontal.text, detail: qsTranslate("Main", "Image"),
          enabled: actions.flipHorizontal.enabled,
          run: function() { actions.flipHorizontal.trigger() } },
        { title: actions.flipVertical.text, detail: qsTranslate("Main", "Image"),
          enabled: actions.flipVertical.enabled,
          run: function() { actions.flipVertical.trigger() } },
        { title: qsTranslate("Main", "Auto enhance"), detail: qsTranslate("Main", "Image"),
          enabled: hasImage && !busy,
          run: function() { catalog.autoEnhanceRequested() } },
        { title: actions.crop.text, detail: qsTranslate("Main", "Tools"),
          shortcut: "C", enabled: actions.crop.enabled,
          run: function() { actions.crop.trigger() } },
        { title: actions.pan.text, detail: qsTranslate("Main", "Tools"),
          shortcut: "H", enabled: actions.pan.enabled,
          run: function() { actions.pan.trigger() } },
        { title: actions.select.text, detail: qsTranslate("Main", "Tools"),
          shortcut: "V", enabled: actions.select.enabled,
          run: function() { actions.select.trigger() } },
        { title: actions.brush.text, detail: qsTranslate("Main", "Tools"),
          shortcut: "B", enabled: actions.brush.enabled,
          run: function() { actions.brush.trigger() } },
        { title: actions.shape.text, detail: qsTranslate("Main", "Tools"),
          shortcut: "U", enabled: actions.shape.enabled,
          run: function() { actions.shape.trigger() } },
        { title: actions.text.text, detail: qsTranslate("Main", "Tools"),
          shortcut: "T", enabled: actions.text.enabled,
          run: function() { actions.text.trigger() } },
        { title: actions.eyedropper.text, detail: qsTranslate("Main", "Tools"),
          shortcut: "I", enabled: actions.eyedropper.enabled,
          run: function() { actions.eyedropper.trigger() } },
        { title: actions.resizeImage.text, detail: qsTranslate("Main", "Image"),
          enabled: actions.resizeImage.enabled,
          run: function() { actions.resizeImage.trigger() } },
        { title: actions.canvasSize.text, detail: qsTranslate("Main", "Image"),
          enabled: actions.canvasSize.enabled,
          run: function() { actions.canvasSize.trigger() } },
        { title: actions.shortcuts.text, detail: qsTranslate("Main", "Help"),
          shortcut: "F1",
          run: function() { actions.shortcuts.trigger() } },
        { title: actions.settings.text, detail: qsTranslate("Main", "Help"),
          shortcut: "Ctrl+,",
          run: function() { actions.settings.trigger() } },
        { title: actions.zoomIn.text, detail: qsTranslate("Main", "View"),
          shortcut: "Ctrl+=", enabled: actions.zoomIn.enabled,
          run: function() { actions.zoomIn.trigger() } },
        { title: actions.zoomOut.text, detail: qsTranslate("Main", "View"),
          shortcut: "Ctrl+-", enabled: actions.zoomOut.enabled,
          run: function() { actions.zoomOut.trigger() } },
        { title: actions.fit.text, detail: qsTranslate("Main", "View"),
          shortcut: "Ctrl+0", enabled: actions.fit.enabled,
          run: function() { actions.fit.trigger() } },
        { title: actions.actual.text, detail: qsTranslate("Main", "View"),
          shortcut: "Ctrl+1", enabled: actions.actual.enabled,
          run: function() { actions.actual.trigger() } },
        { title: qsTranslate("Main", "Toggle dark theme"), detail: qsTranslate("Main", "View"),
          run: function() { catalog.toggleDarkThemeRequested() } },
        { title: qsTranslate("Main", "Follow system theme"), detail: qsTranslate("Main", "View"),
          run: function() { catalog.toggleFollowSystemThemeRequested() } },
        { title: qsTranslate("Main", "Toggle reduce motion"), detail: qsTranslate("Main", "View"),
          run: function() { catalog.toggleReduceMotionRequested() } },
        { title: qsTranslate("Main", "Switch to English"), detail: qsTranslate("Main", "Language"),
          enabled: languageAvailable,
          run: function() { catalog.languageSelected("en") } },
        { title: qsTranslate("Main", "切换到简体中文"), detail: qsTranslate("Main", "Language"),
          enabled: languageAvailable,
          run: function() { catalog.languageSelected("zh_CN") } }
    ].concat(recentEntries.map(function(entry) {
        return { title: entry.name, detail: qsTranslate("Main", "Recent"),
                 enabled: !busy,
                 run: function() { catalog.recentRequested(entry.url) } }
    }))
}
