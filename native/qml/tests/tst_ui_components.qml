import QtQuick
import QtTest
import "../UI"

/*!
    Design-system contract tests.

    Covers token sanity, singleton loading, every component instantiating,
    the shared interaction contract (click/disabled/focus/keys), slider
    gesture ordering, theme switching, reduced motion and a rendering smoke
    test for the gallery.
*/
TestCase {
    name: "UIComponents"
    when: windowShown
    visible: true
    width: 1100
    height: 900

    Component { id: buttonComponent; NekoButton {} }
    Component { id: iconButtonComponent; NekoIconButton {} }
    Component { id: toolButtonComponent; NekoToolButton {} }
    Component { id: segmentedComponent; NekoSegmentedControl {} }
    Component { id: sliderComponent; NekoSlider {} }
    Component { id: toggleComponent; NekoToggle {} }
    Component { id: panelComponent; NekoPanel {} }
    Component { id: cardComponent; NekoCard {} }
    Component { id: sectionHeaderComponent; NekoSectionHeader {} }
    Component { id: scrollBarComponent; NekoScrollBar {} }
    Component { id: dialogComponent; NekoDialog {} }
    Component { id: iconComponent; NekoIcon {} }
    Component { id: galleryComponent; Gallery {} }
    Component { id: spyComponent; SignalSpy {} }

    function init() {
        Theme.dark = true
        Theme.reduceMotion = false
    }

    function make(component, props) {
        return createTemporaryObject(component, this, props)
    }

    function test_bipolarSliderFillsFromOrigin() {
        const slider = createTemporaryObject(sliderComponent, this, {
            width: 200, from: -100, to: 100, origin: 0, value: 0
        })
        verify(slider !== null)
        fuzzyCompare(slider.position, 0.5, 0.001)
        fuzzyCompare(slider.originPosition, 0.5, 0.001)
        fuzzyCompare(slider.fillWidth, 0, 0.001)
        slider.value = 50
        fuzzyCompare(slider.fillFrom, 0.5, 0.001)
        fuzzyCompare(slider.fillWidth, 0.25, 0.001)
    }

    function test_singletonsAndTokens() {
        verify(Theme !== null)
        verify(Motion !== null)

        compare(Theme.spacingXs, 4)
        compare(Theme.spacingSm, 8)
        compare(Theme.spacingMd, 12)
        compare(Theme.spacingLg, 16)
        compare(Theme.spacingXl, 20)
        compare(Theme.spacing2xl, 24)
        compare(Theme.spacing3xl, 32)
        compare(Theme.spacing4xl, 40)

        compare(Theme.radiusXs, 4)
        compare(Theme.radiusSm, 6)
        compare(Theme.radiusMd, 8)
        compare(Theme.radiusLg, 12)
        compare(Theme.radiusXl, 16)
        verify(Theme.radiusPill > Theme.radiusXl)

        compare(Theme.fontCaption, 10)
        compare(Theme.fontSmall, 11)
        compare(Theme.fontBody, 12)
        compare(Theme.fontTitle, 15)
        compare(Theme.fontHeadline, 19)
        compare(Theme.fontDisplay, 24)
        compare(Theme.fontWeightRegular, Font.Normal)
        compare(Theme.fontWeightMedium, Font.Medium)
        compare(Theme.fontWeightDemiBold, Font.DemiBold)
        compare(Theme.fontWeightBold, Font.Bold)

        compare(Motion.instant, 90)
        compare(Motion.fast, 140)
        compare(Motion.standard, 200)
        compare(Motion.slow, 280)
        verify(Motion.instant < Motion.fast)
        verify(Motion.fast < Motion.standard)
        verify(Motion.standard < Motion.slow)
        verify(Motion.standardEasing !== undefined)
        verify(Motion.decelerateEasing !== undefined)
        verify(Motion.accelerateEasing !== undefined)
        verify(Motion.emphasizedEasing !== undefined)
        verify(Motion.springStiffness > 0)
        verify(Motion.springDamping > 0)
        compare(Motion.reduceMotion, false)

        verify(Theme.background.a > 0)
        verify(Theme.textPrimary.a > 0)
        verify(!Qt.colorEqual(Theme.background, Theme.canvas))
        verify(!Qt.colorEqual(Theme.surface, Theme.surfaceRaised))
        verify(Theme.elevationLow.opacity > 0)
        verify(Theme.elevationHigh.opacity > Theme.elevationLow.opacity)
        verify(Theme.opacityDisabled > 0 && Theme.opacityDisabled < 1)

        // contrastColor returns opposite ink/paper extremes.
        verify(Qt.colorEqual(Theme.contrastColor(Theme.contrastInk), Theme.contrastPaper))
        verify(Qt.colorEqual(Theme.contrastColor(Theme.contrastPaper), Theme.contrastInk))
    }

    function test_everyComponentInstantiates() {
        const instances = [
            make(buttonComponent, { text: "Save" }),
            make(iconButtonComponent, { iconName: "close" }),
            make(toolButtonComponent, { iconName: "crop", text: "Crop" }),
            make(segmentedComponent, { model: ["A", "B"], width: 200 }),
            make(sliderComponent, { width: 200 }),
            make(toggleComponent, { text: "On" }),
            make(panelComponent, { width: 200, height: 80 }),
            make(cardComponent, { width: 200, height: 80 }),
            make(sectionHeaderComponent, { width: 200, text: "Section" }),
            make(scrollBarComponent, { width: 8, height: 120 }),
            make(dialogComponent, { title: "Dialog" }),
            make(iconComponent, { name: "logo" }),
            make(galleryComponent, { width: 900, height: 700 })
        ]
        for (let i = 0; i < instances.length; ++i)
            verify(instances[i] !== null, "component " + i + " failed to instantiate")
    }

    function test_iconSetPaints() {
        const icon = make(iconComponent, { x: 20, y: 20, name: "logo", width: 24, height: 24 })
        verify(icon !== null)
        const names = [
            "logo", "folder", "save", "undo", "redo", "rotate", "crop", "adjust",
            "filters", "brush", "text", "shapes", "mosaic", "select", "pan",
            "close", "check", "chevronDown", "chevronUp", "chevronLeft",
            "chevronRight", "plus", "minus", "reset", "eye", "eyeOff"
        ]
        for (let i = 0; i < names.length; ++i) {
            icon.name = names[i]
            verify(waitForRendering(icon), "icon failed to render: " + names[i])
        }
    }

    function test_accessibilityMetadata() {
        const button = make(buttonComponent, { text: "Save", accessibleName: "Save image" })
        compare(button.Accessible.role, Accessible.Button)
        compare(button.Accessible.name, "Save image")

        const iconButton = make(iconButtonComponent, { accessibleName: "Close" })
        compare(iconButton.Accessible.role, Accessible.Button)
        compare(iconButton.Accessible.name, "Close")

        const tool = make(toolButtonComponent, { iconName: "crop", text: "Crop" })
        compare(tool.Accessible.role, Accessible.Button)
        compare(tool.Accessible.name, "Crop")

        const segmented = make(segmentedComponent, { model: ["A"], accessibleName: "Sections" })
        compare(segmented.Accessible.role, Accessible.PageTabList)
        compare(segmented.Accessible.name, "Sections")

        const slider = make(sliderComponent, { accessibleName: "Exposure" })
        compare(slider.Accessible.role, Accessible.Slider)
        compare(slider.Accessible.name, "Exposure")

        const toggle = make(toggleComponent, { text: "Local" })
        compare(toggle.Accessible.role, Accessible.CheckBox)
        compare(toggle.Accessible.name, "Local")

        const panel = make(panelComponent, { accessibleName: "Panel" })
        compare(panel.Accessible.role, Accessible.Pane)
        compare(panel.Accessible.name, "Panel")

        const card = make(cardComponent, { accessibleName: "Card" })
        compare(card.Accessible.role, Accessible.Button)
        compare(card.Accessible.name, "Card")

        const header = make(sectionHeaderComponent, { text: "Actions" })
        compare(header.Accessible.role, Accessible.Heading)
        compare(header.Accessible.name, "Actions")

        const scroll = make(scrollBarComponent, { width: 8, height: 120 })
        compare(scroll.Accessible.role, Accessible.ScrollBar)

        // Popup is not an Item, so NekoDialog exposes metadata on its content.
        const dialog = make(dialogComponent, { title: "Export" })
        compare(dialog.contentItem.Accessible.role, Accessible.Dialog)
        compare(dialog.contentItem.Accessible.name, "Export")
    }

    function test_buttonClicksAndDisabledBlocks() {
        const button = make(buttonComponent, {
            x: 40, y: 40, text: "Save", variant: "primary", iconName: "save"
        })
        verify(button !== null)
        verify(waitForRendering(button))

        const spy = make(spyComponent, { target: button, signalName: "clicked" })
        verify(spy !== null)

        mouseClick(button)
        compare(spy.count, 1)

        button.enabled = false
        mouseClick(button)
        compare(spy.count, 1)

        button.enabled = true
        button.forceActiveFocus()
        keyClick(Qt.Key_Space)
        compare(spy.count, 2)

        verify(button.implicitWidth > Theme.controlHeight)
        verify(Qt.colorEqual(button.fill, Theme.accent))
    }

    function test_segmentedControlSelection() {
        const segmented = make(segmentedComponent, {
            x: 40, y: 40, width: 270, model: ["One", "Two", "Three"]
        })
        verify(segmented !== null)
        verify(waitForRendering(segmented))
        compare(segmented.selectedIndex, 0)

        const activated = make(spyComponent, { target: segmented, signalName: "activated" })
        const changed = make(spyComponent, { target: segmented, signalName: "selectionChanged" })

        const second = findChild(segmented, "segment-1")
        verify(second !== null)
        mouseClick(second)
        compare(segmented.currentIndex, 1)
        compare(activated.count, 1)
        compare(activated.signalArguments[0][0], 1)
        compare(changed.count, 1)

        segmented.forceActiveFocus()
        keyClick(Qt.Key_Right)
        compare(segmented.currentIndex, 2)
        compare(activated.count, 2)

        keyClick(Qt.Key_Left)
        compare(segmented.currentIndex, 1)
        compare(activated.count, 3)
    }

    function test_sliderGestureAndKeyboard() {
        const slider = make(sliderComponent, {
            x: 40, y: 40, width: 240,
            from: 0, to: 100, value: 0, stepSize: 1, defaultValue: 0
        })
        verify(slider !== null)
        verify(waitForRendering(slider))

        const events = []
        slider.begin.connect(function() { events.push("begin") })
        slider.preview.connect(function(value) { events.push("preview") })
        slider.finish.connect(function(value) { events.push("finish") })

        // Drag from near the left edge to beyond the right end.
        mousePress(slider, 20, slider.height / 2)
        mouseMove(slider, slider.width - 2, slider.height / 2)
        mouseRelease(slider, slider.width - 2, slider.height / 2)

        verify(events.length >= 3, "expected begin/preview/finish, got " + events)
        compare(events[0], "begin")
        compare(events[events.length - 1], "finish")
        verify(events.indexOf("preview") > 0)
        compare(slider.value, 100)

        // Keyboard commits a complete gesture.
        events.length = 0
        slider.value = 40
        slider.forceActiveFocus()
        keyClick(Qt.Key_Right)
        compare(slider.value, 41)
        compare(events.length, 3)
        compare(events[0], "begin")
        compare(events[1], "preview")
        compare(events[2], "finish")

        // Double-click resets to defaultValue.
        events.length = 0
        slider.value = 10
        mouseDoubleClickSequence(slider, slider.width / 2, slider.height / 2)
        compare(slider.value, slider.defaultValue)
        verify(events.length >= 3)
    }

    function test_toggleAndCardKeyboard() {
        const toggle = make(toggleComponent, {
            x: 40, y: 40, text: "Local editing", accessibleName: "Local editing"
        })
        verify(toggle !== null)
        verify(waitForRendering(toggle))
        verify(!toggle.checked)

        mouseClick(toggle)
        verify(toggle.checked)

        const before = toggle.checked
        toggle.enabled = false
        mouseClick(toggle)
        compare(toggle.checked, before)

        const card = make(cardComponent, { x: 40, y: 120, width: 200, height: 100 })
        verify(card !== null)
        const spy = make(spyComponent, { target: card, signalName: "clicked" })
        mouseClick(card)
        compare(spy.count, 1)

        card.forceActiveFocus()
        keyClick(Qt.Key_Space)
        compare(spy.count, 2)
    }

    function test_themeSwitchUpdatesComponents() {
        const button = make(buttonComponent, { x: 40, y: 40, text: "Save" })
        verify(button !== null)
        // Snapshot as strings: QML colour values read through a singleton can
        // remain live references in the JS engine.
        const darkBackground = Theme.background.toString()
        const darkInk = button.ink.toString()

        verify(Theme.dark)
        verify(Qt.colorEqual(Theme.background, "#181a1b"))

        Theme.dark = false
        verify(!Theme.dark)
        verify(Theme.background.toString() !== darkBackground)
        verify(button.ink.toString() !== darkInk)
        verify(Qt.colorEqual(Theme.background, "#edece8"))
        verify(Qt.colorEqual(Theme.textPrimary, "#303734"))

        Theme.dark = true
        verify(Qt.colorEqual(Theme.background, "#181a1b"))
        verify(Qt.colorEqual(Theme.textPrimary, "#e9e9e6"))
    }

    function test_reduceMotionStopsAnimations() {
        compare(Motion.duration(Motion.fast), 140)
        compare(Motion.duration(Motion.standard), 200)
        compare(Motion.duration(Motion.slow), 280)

        Theme.reduceMotion = true
        verify(Motion.reduceMotion)
        compare(Motion.duration(Motion.instant), 0)
        compare(Motion.duration(Motion.fast), 0)
        compare(Motion.duration(Motion.standard), 0)
        compare(Motion.duration(Motion.slow), 0)

        Theme.reduceMotion = false
        verify(!Motion.reduceMotion)
        compare(Motion.duration(Motion.fast), 140)
    }

    function test_noBindingLoopWarnings() {
        failOnWarning(/binding loop/i)

        const gallery = make(galleryComponent, { x: 0, y: 0, width: 1000, height: 800 })
        verify(gallery !== null)
        verify(waitForRendering(gallery))

        Theme.dark = false
        verify(waitForRendering(gallery))

        Theme.reduceMotion = true
        verify(waitForRendering(gallery))

        Theme.reduceMotion = false
        Theme.dark = true
        verify(waitForRendering(gallery))
    }

    function test_visualSmokeGrab() {
        const gallery = make(galleryComponent, { x: 0, y: 0, width: 980, height: 760 })
        verify(gallery !== null)
        verify(waitForRendering(gallery))

        let grabbed = false
        let result = null
        gallery.grabToImage(function(image) {
            result = image
            grabbed = true
        })

        if (!grabbed)
            tryVerify(function() { return grabbed }, 3000)

        if (!grabbed || result === null) {
            skip("grabToImage is not supported by this platform")
            return
        }

        verify(result !== null)
    }
}
