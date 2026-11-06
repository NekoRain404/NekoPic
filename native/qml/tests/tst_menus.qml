import QtQuick
import QtQuick.Controls
import QtTest
import "../UI"
import "../shell"

/*!
    Menu and combo-popup contract tests.

    Covers the shared surface, row metrics, action/shortcut bindings,
    checkable state, submenu navigation, combo-box selection and keyboard
    handling, theme switching, and the seven-menu AppMenuBar composition.
*/
TestCase {
    id: testCase
    name: "Menus"
    when: windowShown
    visible: true
    width: 1100
    height: 800

    Action { id: saveAction; text: "Save"; shortcut: "Ctrl+S" }
    Action { id: openAction; text: "Open image…"; shortcut: "Ctrl+O" }
    Action { id: saveAsAction; text: "Save as…"; shortcut: "Ctrl+Shift+S" }
    Action { id: undoAction; text: "Undo"; shortcut: "Ctrl+Z" }
    Action { id: redoAction; text: "Redo"; shortcut: "Ctrl+Shift+Z" }
    Action { id: copyAction; text: "Copy image"; shortcut: "Ctrl+Shift+C" }
    Action { id: settingsAction; text: "Preferences…"; shortcut: "Ctrl+," }
    Action { id: rotateLeftAction; text: "Rotate counterclockwise" }
    Action { id: rotateRightAction; text: "Rotate clockwise" }
    Action { id: flipHAction; text: "Flip horizontally" }
    Action { id: flipVAction; text: "Flip vertically" }
    Action { id: resizeAction; text: "Resize image…" }
    Action { id: canvasAction; text: "Canvas size…" }
    Action { id: selectAction; text: "Select"; shortcut: "V" }
    Action { id: panAction; text: "Pan"; shortcut: "H" }
    Action { id: brushAction; text: "Brush"; shortcut: "B" }
    Action { id: textAction; text: "Add text"; shortcut: "T" }
    Action { id: shapeAction; text: "Shapes"; shortcut: "U" }
    Action { id: eyedropperAction; text: "Eyedropper"; shortcut: "I" }
    Action { id: cropAction; text: "Crop"; shortcut: "C" }
    Action { id: zoomInAction; text: "Zoom in"; shortcut: "Ctrl+=" }
    Action { id: zoomOutAction; text: "Zoom out"; shortcut: "Ctrl+-" }
    Action { id: fitAction; text: "Fit to window"; shortcut: "Ctrl+0" }
    Action { id: actualAction; text: "Actual size (100%)"; shortcut: "Ctrl+1" }
    Action { id: paletteAction; text: "Command palette…"; shortcut: "Ctrl+K" }
    Action { id: shortcutsAction; text: "Keyboard shortcuts"; shortcut: "F1" }

    readonly property var actionMap: ({
        open: openAction, save: saveAction, saveAs: saveAsAction,
        undo: undoAction, redo: redoAction, copy: copyAction,
        settings: settingsAction,
        rotateLeft: rotateLeftAction, rotateRight: rotateRightAction,
        flipHorizontal: flipHAction, flipVertical: flipVAction,
        resizeImage: resizeAction, canvasSize: canvasAction,
        select: selectAction, pan: panAction, brush: brushAction,
        text: textAction, shape: shapeAction,
        eyedropper: eyedropperAction, crop: cropAction,
        zoomIn: zoomInAction, zoomOut: zoomOutAction,
        fit: fitAction, actual: actualAction,
        commandPalette: paletteAction, shortcuts: shortcutsAction
    })

    Component { id: spyComponent; SignalSpy {} }

    Component {
        id: menuComponent
        NekoMenu {
            objectName: "testMenu"
            NekoMenuItem { objectName: "item-save"; action: saveAction }
            NekoMenuItem { objectName: "item-check"; text: "Show grid"; checkable: true }
            NekoMenuSeparator { objectName: "item-separator" }
            NekoMenu {
                objectName: "item-submenu"
                title: "More"
                NekoMenuItem { objectName: "item-submenu-child"; text: "Nested action" }
            }
        }
    }

    Component {
        id: comboComponent
        NekoComboBox { objectName: "testCombo" }
    }

    Component {
        id: barComponent
        AppMenuBar {}
    }

    function init() {
        Theme.dark = true
        Theme.themeId = ""
        Theme.reduceMotion = true
    }

    function make(component, props) {
        return createTemporaryObject(component, this, props || {})
    }

    function spy(target, signalName) {
        return createTemporaryObject(spyComponent, testCase,
                                     { target: target, signalName: signalName })
    }

    function openMenu(menu) {
        menu.open()
        tryVerify(function() { return menu.opened }, 1500)
        wait(20)
    }

    function closeMenu(menu) {
        menu.close()
        tryVerify(function() { return !menu.opened }, 1500)
    }

    // ── Surface and metrics ─────────────────────────────────────────────────

    function test_menuSurfaceObjectNamesAndMetrics() {
        const menu = make(menuComponent, {})
        verify(menu !== null)

        const surface = findChild(menu, "neko-menu-surface")
        const content = findChild(menu, "neko-menu-content")
        verify(surface !== null)
        verify(content !== null)
        compare(content.objectName, "neko-menu-content")
        compare(content.count, menu.count)

        const item = findChild(menu, "item-save")
        verify(item !== null)
        compare(item.objectName, "item-save")
        compare(item.implicitHeight, 30)
        compare(item.leftPadding, Theme.spacingMd)
        compare(item.rightPadding, Theme.spacingMd)
        verify(item.effectiveShortcut.length > 0)

        const separator = findChild(menu, "item-separator")
        verify(separator !== null)
        compare(separator.objectName, "item-separator")
        const line = findChild(separator, "neko-menu-separator-line")
        verify(line !== null)
        compare(line.height, Theme.borderWidth)

        verify(menu.width >= menu.minWidth)
    }

    function test_menuOpenClose() {
        const menu = make(menuComponent, {})
        verify(!menu.opened)
        openMenu(menu)
        verify(menu.opened)
        closeMenu(menu)
        verify(!menu.opened)
    }

    // ── Activation, actions and shortcuts ───────────────────────────────────

    function test_itemActivationEmitsAndClosesMenu() {
        const menu = make(menuComponent, {})
        const item = findChild(menu, "item-save")
        const triggered = spy(item, "triggered")

        openMenu(menu)
        mouseClick(item)
        wait(20)

        compare(triggered.count, 1)
        verify(!menu.opened)
    }

    function test_actionBindingAndShortcutLabel() {
        const menu = make(menuComponent, {})
        const item = findChild(menu, "item-save")
        compare(item.action, saveAction)
        compare(item.text, "Save")
        compare(item.effectiveShortcut, "Ctrl+S")

        openMenu(menu)
        const label = findChild(item, "neko-menu-item-label")
        const shortcut = findChild(item, "neko-menu-item-shortcut")
        verify(label !== null && shortcut !== null)
        compare(label.text, "Save")
        compare(shortcut.text, "Ctrl+S")
        verify(shortcut.visible)
        verify(shortcut.x > label.x)
        verify(shortcut.x + shortcut.width <= item.width - item.rightPadding + 1)
        closeMenu(menu)
    }

    function test_checkableToggleAndCheckmark() {
        const menu = make(menuComponent, {})
        const item = findChild(menu, "item-check")
        const check = findChild(item, "neko-menu-item-check")
        verify(check !== null)
        verify(!item.checked)

        openMenu(menu)
        verify(!check.visible)
        mouseClick(item)
        wait(20)
        verify(item.checked)

        openMenu(menu)
        verify(check.visible)
        mouseClick(item)
        wait(20)
        verify(!item.checked)

        openMenu(menu)
        verify(!check.visible)
        closeMenu(menu)
    }

    // ── Submenus ────────────────────────────────────────────────────────────

    function test_submenuNavigation() {
        const menu = make(menuComponent, {})
        const submenu = findChild(menu, "item-submenu")
        verify(submenu !== null)
        verify(submenu.subMenu !== null)

        openMenu(menu)
        const row = menu.itemAt(3)
        verify(row !== null)
        verify(row.subMenu !== null)
        const arrow = findChild(row, "neko-menu-item-arrow")
        verify(arrow !== null)
        verify(arrow.visible)

        row.subMenu.open()
        tryVerify(function() { return row.subMenu.opened }, 1500)
        wait(20)
        verify(findChild(row.subMenu, "neko-menu-surface") !== null)
        const child = findChild(row.subMenu, "item-submenu-child")
        verify(child !== null)
        compare(child.text, "Nested action")

        const triggered = spy(child, "triggered")
        mouseClick(child)
        wait(20)
        compare(triggered.count, 1)
        verify(!row.subMenu.opened)
    }

    // ── Separator and theme tokens ──────────────────────────────────────────

    function test_surfaceAndSeparatorFollowTheme() {
        const menu = make(menuComponent, {})
        const surface = findChild(menu, "neko-menu-surface")
        const separator = findChild(menu, "item-separator")
        const line = findChild(separator, "neko-menu-separator-rule")

        verify(Qt.colorEqual(surface.backgroundColor, Theme.surfaceRaised))
        verify(Qt.colorEqual(line.color, Theme.separator))

        Theme.dark = false
        verify(Qt.colorEqual(surface.backgroundColor, Theme.surfaceRaised))
        verify(Qt.colorEqual(line.color, Theme.separator))

        Theme.themeId = "midnight"
        verify(Qt.colorEqual(surface.backgroundColor, Theme.surfaceRaised))
        verify(Qt.colorEqual(line.color, Theme.separator))

        Theme.themeId = "warm"
        verify(Qt.colorEqual(surface.backgroundColor, Theme.surfaceRaised))

        Theme.themeId = ""
        Theme.dark = true
    }

    // ── ComboBox ────────────────────────────────────────────────────────────

    function test_comboBoxSelectionAndKeyboard() {
        const combo = make(comboComponent, {
            x: 20, y: 20, width: 240,
            model: ["One", "Two", "Three"], currentIndex: 0
        })
        verify(combo !== null)
        compare(combo.displayText, "One")
        verify(findChild(combo, "neko-combo-surface") !== null)

        combo.popup.open()
        tryVerify(function() { return combo.popup.visible }, 1500)
        wait(30)
        const list = findChild(combo.popup, "neko-combo-list")
        verify(list !== null)
        compare(list.count, 3)

        const row = list.itemAtIndex(1)
        verify(row !== null)
        compare(row.height, 30)
        mouseClick(row)
        wait(30)
        compare(combo.currentIndex, 1)
        compare(combo.displayText, "Two")
        verify(!combo.popup.visible)

        // Keyboard: focus the closed field, open, navigate and commit.
        combo.currentIndex = 0
        combo.forceActiveFocus()
        keyClick(Qt.Key_Down)
        compare(combo.currentIndex, 1)
        keyClick(Qt.Key_Up)
        compare(combo.currentIndex, 0)

        keyClick(Qt.Key_Space)
        tryVerify(function() { return combo.popup.visible }, 1500)
        wait(20)
        keyClick(Qt.Key_Down)
        compare(combo.highlightedIndex, 1)
        keyClick(Qt.Key_Return)
        tryVerify(function() { return !combo.popup.visible }, 1500)
        compare(combo.currentIndex, 1)
        compare(combo.displayText, "Two")
    }

    function test_comboBoxAccessibilityAndObjectNames() {
        const combo = make(comboComponent, {
            model: ["One", "Two"],
            accessibleName: "Font family",
            accessibleDescription: "Typeface used to render the text"
        })
        compare(combo.Accessible.role, Accessible.ComboBox)
        compare(combo.Accessible.name, "Font family")
        compare(combo.Accessible.description, "Typeface used to render the text")
        verify(!combo.Accessible.expanded)

        combo.popup.open()
        tryVerify(function() { return combo.popup.visible }, 1500)
        verify(combo.Accessible.expanded)
        verify(findChild(combo.popup, "neko-combo-popup-surface") !== null)
        verify(findChild(combo.popup, "neko-combo-list") !== null)
        combo.popup.close()
    }

    // ── Menu bar composition and signals ────────────────────────────────────

    function test_appMenuBarHasSevenMenusAndNestedState() {
        const bar = make(barComponent, {
            width: 1100,
            actions: actionMap,
            hasImage: true,
            recentEntries: [
                { name: "first.png", url: "file:///tmp/first.png" },
                { name: "second.png", url: "file:///tmp/second.png" }
            ],
            availableLocales: [
                { id: "en", nativeName: "English" },
                { id: "zh_CN", nativeName: "中文" }
            ],
            localeId: "zh_CN"
        })
        verify(bar !== null)
        compare(bar.count, 7)

        const titles = ["File", "Edit", "Image", "Tools", "Adjust", "View", "Help"]
        for (let i = 0; i < titles.length; ++i)
            compare(bar.menuAt(i).title, titles[i])

        const file = findChild(bar, "menu-file")
        const recent = findChild(bar, "recentMenu")
        verify(file !== null && recent !== null)
        verify(recent.enabled)
        compare(recent.count, 4)

        const view = findChild(bar, "menu-view")
        const language = findChild(bar, "languageMenu")
        verify(view !== null && language !== null)
        openMenu(view)
        language.open()
        tryVerify(function() { return language.opened }, 1500)
        compare(language.count, 2)
        verify(findChild(language, "neko-menu-surface") !== null)
        language.close()
        closeMenu(view)
    }

    function test_appMenuBarMenusAttachToTheirTrigger() {
        const bar = make(barComponent, {
            width: 1100,
            actions: actionMap,
            hasImage: true
        })
        verify(bar !== null)
        wait(20)

        const triggerByText = ({})
        const children = bar.contentItem.children
        for (let i = 0; i < children.length; ++i) {
            if (children[i].text !== undefined)
                triggerByText[children[i].text] = children[i]
        }

        const items = [
            { text: "File", name: "menu-file" },
            { text: "Edit", name: "menu-edit" },
            { text: "Image", name: "menu-image" },
            { text: "Tools", name: "menu-tools" },
            { text: "Adjust", name: "menu-adjust" },
            { text: "View", name: "menu-view" },
            { text: "Help", name: "menu-help" }
        ]
        for (let i = 0; i < items.length; ++i) {
            const trigger = triggerByText[items[i].text]
            const menu = findChild(bar, items[i].name)
            verify(trigger !== undefined, "missing trigger " + items[i].text)
            verify(menu !== null, "missing menu " + items[i].name)
            // Menu bars parent each popup to its trigger item, so opening at
            // x = 0 keeps the surface aligned under the label.
            compare(menu.parent, trigger)
            compare(menu.x, 0)
        }
    }

    function test_appMenuBarSignals() {
        const bar = make(barComponent, {
            width: 1100,
            actions: actionMap,
            hasImage: true
        })
        const toolSpy = spy(bar, "toolRequested")
        const autoSpy = spy(bar, "autoEnhanceRequested")
        const aboutSpy = spy(bar, "aboutRequested")

        const tools = findChild(bar, "menu-tools")
        openMenu(tools)
        mouseClick(findChild(bar, "menu-mosaic"))
        wait(20)
        compare(toolSpy.count, 1)
        compare(toolSpy.signalArguments[0][0], "mosaic")

        const adjust = findChild(bar, "menu-adjust")
        openMenu(adjust)
        mouseClick(findChild(bar, "menu-adjust-colour"))
        wait(20)
        compare(toolSpy.count, 2)
        compare(toolSpy.signalArguments[1][0], "adjust")

        openMenu(adjust)
        mouseClick(findChild(bar, "menu-adjust-filters"))
        wait(20)
        compare(toolSpy.count, 3)
        compare(toolSpy.signalArguments[2][0], "filters")

        openMenu(adjust)
        mouseClick(findChild(bar, "menu-adjust-auto-enhance"))
        wait(20)
        compare(autoSpy.count, 1)

        const help = findChild(bar, "menu-help")
        openMenu(help)
        mouseClick(findChild(bar, "menu-about"))
        wait(20)
        compare(aboutSpy.count, 1)
    }

    function test_appMenuBarExistingSignalsPreserved() {
        const bar = make(barComponent, {
            width: 1100,
            actions: actionMap,
            hasImage: true,
            followSystemTheme: false,
            darkTheme: true,
            reduceMotion: false,
            availableLocales: [{ id: "en", nativeName: "English" }],
            localeId: "en"
        })
        const followSpy = spy(bar, "followSystemThemeToggled")
        const localeSpy = spy(bar, "localeSelected")

        const view = findChild(bar, "menu-view")
        const theme = findChild(bar, "themeMenu")
        openMenu(view)
        theme.open()
        tryVerify(function() { return theme.opened }, 1500)
        mouseClick(findChild(bar, "menu-theme-follow-system"))
        wait(20)
        compare(followSpy.count, 1)
        compare(followSpy.signalArguments[0][0], true)

        openMenu(view)
        const language = findChild(bar, "languageMenu")
        language.open()
        tryVerify(function() { return language.opened }, 1500)
        const localeRow = language.itemAt(0)
        verify(localeRow !== null)
        mouseClick(localeRow)
        wait(20)
        compare(localeSpy.count, 1)
        compare(localeSpy.signalArguments[0][0], "en")
    }

    function test_noBindingLoopWarnings() {
        failOnWarning(/binding loop/i)
        const menu = make(menuComponent, {})
        openMenu(menu)
        closeMenu(menu)

        const combo = make(comboComponent, {
            x: 20, y: 20, width: 240, model: ["One", "Two", "Three"]
        })
        combo.popup.open()
        tryVerify(function() { return combo.popup.visible }, 1500)
        combo.popup.close()
    }
}
