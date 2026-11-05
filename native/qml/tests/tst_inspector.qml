import QtQuick
import QtTest
import ".."

TestCase {
    name: "InspectorAdjustments"
    when: windowShown
    visible: true
    width: 320
    height: 700

    Inspector {
        id: inspector
        width: 292
        height: 680
        theme: ({ panel: "#222222", raised: "#333333", hover: "#444444",
                  background: "#181818", border: "#555555", text: "#ffffff", muted: "#aaaaaa", accent: "#edbc9d" })
    }
    SignalSpy { id: started; target: inspector; signalName: "adjustmentStarted" }
    SignalSpy { id: preview; target: inspector; signalName: "adjustmentPreview" }
    SignalSpy { id: finished; target: inspector; signalName: "adjustmentFinished" }
    SignalSpy { id: reset; target: inspector; signalName: "adjustmentReset" }
    SignalSpy { id: autoEnhance; target: inspector; signalName: "autoEnhanceRequested" }
    SignalSpy { id: filterSelected; target: inspector; signalName: "filterSelected" }
    SignalSpy { id: filterStarted; target: inspector; signalName: "filterIntensityStarted" }
    SignalSpy { id: filterPreview; target: inspector; signalName: "filterIntensityPreview" }
    SignalSpy { id: filterFinished; target: inspector; signalName: "filterIntensityFinished" }
    Connections {
        target: inspector
        enabled: false
        id: previewNotification
        function onAdjustmentPreview(key, value) {
            inspector.adjustmentValues = ({ exposure: 0, brightness: 0, contrast: 0, saturation: 0 })
        }
    }

    function defaultValues() {
        const values = {
            exposure: 0, brightness: 0, contrast: 0, saturation: 0,
            highlights: 0, shadows: 0, whites: 0, blacks: 0,
            temperature: 0, tint: 0, vibrance: 0,
            texture: 0, clarity: 0, dehaze: 0, sharpen: 0,
            noise: 0, colorNoise: 0, vignette: 0, feather: 50, grain: 0, fade: 0,
            "grade.blending": 50, "grade.balance": 0
        }
        const hslChannels = ["red", "orange", "yellow", "green", "aqua", "blue", "purple", "magenta"]
        for (let c = 0; c < hslChannels.length; ++c) {
            values["hsl." + hslChannels[c] + ".hue"] = 0
            values["hsl." + hslChannels[c] + ".saturation"] = 0
            values["hsl." + hslChannels[c] + ".luminance"] = 0
        }
        const zones = ["shadows", "midtones", "highlights"]
        for (let z = 0; z < zones.length; ++z) {
            values["grade." + zones[z] + ".hue"] = 0
            values["grade." + zones[z] + ".saturation"] = 0
            values["grade." + zones[z] + ".luminance"] = 0
        }
        const curves = { RGB: [0, 25, 50, 75, 100], R: [0, 25, 50, 75, 100],
                         G: [0, 25, 50, 75, 100], B: [0, 25, 50, 75, 100] }
        for (const channel in curves) {
            for (let i = 0; i < 5; ++i)
                values["curve." + channel + "." + i] = curves[channel][i]
        }
        return values
    }

    function init() {
        started.clear(); preview.clear(); finished.clear(); reset.clear()
        filterSelected.clear(); filterStarted.clear(); filterPreview.clear(); filterFinished.clear()
        inspector.currentTab = 0
        inspector.adjustTab = 0
        previewNotification.enabled = false
        inspector.adjustmentValues = defaultValues()
        inspector.adjustmentsEnabled = true
        inspector.filtersEnabled = true
        inspector.filterPreset = "none"
        inspector.filterIntensity = 100
        const scroll = findChild(inspector, "inspector-scroll")
        if (scroll && scroll.contentItem)
            scroll.contentItem.contentY = 0
        const hsl = findChild(inspector, "hsl-controls")
        if (hsl)
            hsl.channel = "red"
        const grade = findChild(inspector, "grade-controls")
        if (grade)
            grade.zone = "shadows"
        const curve = findChild(inspector, "curve-editor")
        if (curve)
            curve.channel = "RGB"
    }

    function test_committedValuesFollowController() {
        const slider = findChild(inspector, "adjustment-exposure")
        inspector.adjustmentValues = ({ exposure: 35, brightness: 0, contrast: 0, saturation: 0 })
        compare(slider.value, 35)
        inspector.adjustmentValues = ({ exposure: -20, brightness: 0, contrast: 0, saturation: 0 })
        compare(slider.value, -20)
    }

    function test_filterPreviewsUseRevisionAndRetainLabels() {
        inspector.currentTab = 1
        verify(inspector.previewsAvailable !== undefined)
        inspector.previewsAvailable = false
        const warm = findChild(inspector, "filter-preview-warm")
        verify(warm !== null)
        compare(warm.source.toString(), "")
        compare(findChild(inspector, "filter-warm").text, "Warm")
        inspector.previewRevision = 7
        // Standalone QML runner has no C++ provider; pixel delivery is tested in C++.
        for (let i = 0; i < 13; ++i)
            ignoreWarning(/.*Invalid image provider: image:\/\/filterpreview\/.*/)
        inspector.previewsAvailable = true
        compare(warm.source.toString(), "image://filterpreview/warm/7")
        inspector.previewRevision = 8
        compare(warm.source.toString(), "image://filterpreview/warm/8")
        inspector.previewsAvailable = false
        compare(warm.source.toString(), "")
    }

    function test_disabledWithoutImage() {
        inspector.adjustmentsEnabled = false
        verify(!findChild(inspector, "adjustment-exposure").enabled)
        verify(!findChild(inspector, "adjustment-reset").enabled)
    }

    function test_autoEnhanceCommand() {
        inspector.adjustmentsEnabled = true
        const button = findChild(inspector, "adjustment-auto")
        verify(button !== null)
        mouseClick(button)
        compare(autoEnhance.count, 1)
    }

    function test_resetCommand() {
        const button = findChild(inspector, "adjustment-reset")
        mouseClick(button)
        compare(reset.count, 1)
    }

    function test_dragIsOneGesture() {
        const slider = findChild(inspector, "adjustment-exposure")
        verify(slider.enabled)
        mousePress(slider, slider.width / 2, slider.height / 2)
        mouseMove(slider, slider.width * 0.75, slider.height / 2)
        mouseRelease(slider, slider.width * 0.75, slider.height / 2)
        compare(started.count, 1)
        verify(preview.count > 0)
        compare(finished.count, 1)
        compare(finished.signalArguments[0][0], "exposure")
        verify(finished.signalArguments[0][1] > 0)
        verify(slider.value > 0)
    }

    function test_keyboardAdjustment() {
        previewNotification.enabled = true
        const slider = findChild(inspector, "adjustment-brightness")
        slider.forceActiveFocus()
        keyClick(Qt.Key_Right)
        compare(started.count, 1)
        compare(preview.count, 1)
        compare(finished.count, 1)
        compare(finished.signalArguments[0][0], "brightness")
        verify(finished.signalArguments[0][1] > 0)
        verify(slider.value > 0)
    }

    function test_selectingPresetEmitsBackendId() {
        inspector.currentTab = 1
        const button = findChild(inspector, "filter-vintage")
        verify(button !== null)
        mouseClick(button)
        compare(filterSelected.count, 1)
        compare(filterSelected.signalArguments[0][0], "vintage")
    }

    function test_filterIntensityTracksControllerAndGesture() {
        inspector.currentTab = 1
        inspector.filterPreset = "warm"
        inspector.filterIntensity = 42
        const slider = findChild(inspector, "filter-intensity")
        compare(slider.value, 42)
        mousePress(slider, slider.width / 2, slider.height / 2)
        mouseMove(slider, slider.width * 0.75, slider.height / 2)
        mouseRelease(slider, slider.width * 0.75, slider.height / 2)
        compare(filterStarted.count, 1)
        verify(filterPreview.count > 0)
        compare(filterFinished.count, 1)
        compare(filterFinished.signalArguments[0][0], slider.value)
    }

    function test_filtersDisabledWithoutImage() {
        inspector.currentTab = 1
        inspector.filtersEnabled = false
        verify(!findChild(inspector, "filter-vivid").enabled)
        verify(!findChild(inspector, "filter-intensity").enabled)
    }

    function test_filterKeyboardIntensityIsOneGesture() {
        inspector.currentTab = 1
        inspector.filterPreset = "warm"
        inspector.filterIntensity = 42
        const slider = findChild(inspector, "filter-intensity")
        slider.forceActiveFocus()
        keyClick(Qt.Key_Right)
        compare(filterStarted.count, 1)
        compare(filterPreview.count, 1)
        compare(filterFinished.count, 1)
        compare(filterPreview.signalArguments[0][0], 43)
        compare(filterFinished.signalArguments[0][0], 43)
    }

    function test_intensityRemainsEnabledWhilePresetTilesAreLocked() {
        inspector.currentTab = 1
        inspector.filterPreset = "warm"
        verify(inspector.filterIntensityEnabled !== undefined)
        inspector.filterIntensityEnabled = true
        inspector.filtersEnabled = false
        verify(!findChild(inspector, "filter-warm").enabled)
        const slider = findChild(inspector, "filter-intensity")
        verify(slider.enabled)
        slider.forceActiveFocus()
        keyClick(Qt.Key_Left)
        compare(filterFinished.count, 1)
        inspector.filterIntensityEnabled = Qt.binding(function() { return inspector.filtersEnabled })
    }

    // ── Five-tab colour workspace ───────────────────────────────────────────

    function test_fiveAdjustSubTabsExistAndSwitch() {
        compare(inspector.adjustTabLabels.length, 5)
        const bar = findChild(inspector, "adjust-subtabs")
        verify(bar !== null)
        for (let i = 0; i < 5; ++i)
            verify(findChild(inspector, "adjust-subtab-" + i) !== null)

        inspector.adjustTab = 2
        compare(bar.currentIndex, 2)
        mouseClick(findChild(inspector, "adjust-subtab-3"))
        compare(inspector.adjustTab, 3)
        compare(bar.currentIndex, 3)

        bar.forceActiveFocus()
        keyClick(Qt.Key_Left)
        compare(inspector.adjustTab, 2)
        keyClick(Qt.Key_Home)
        compare(inspector.adjustTab, 0)
    }

    function test_basicSlidersEmitKeyAndOneGestureEach() {
        inspector.adjustTab = 0
        const keys = ["exposure", "brightness", "contrast", "highlights", "shadows",
                      "whites", "blacks", "temperature", "tint", "saturation", "vibrance"]
        for (let i = 0; i < keys.length; ++i) {
            started.clear(); preview.clear(); finished.clear()
            const slider = findChild(inspector, "adjustment-" + keys[i])
            verify(slider !== null)
            compare(slider.from, -100)
            compare(slider.to, 100)
            compare(slider.value, 0)
            slider.forceActiveFocus()
            keyClick(Qt.Key_Right)
            compare(started.count, 1)
            compare(preview.count, 1)
            compare(finished.count, 1)
            compare(started.signalArguments[0][0], keys[i])
            compare(preview.signalArguments[0][0], keys[i])
            compare(finished.signalArguments[0][0], keys[i])
            compare(finished.signalArguments[0][1], 1)
        }
    }

    function test_basicValuesFollowController() {
        inspector.adjustTab = 0
        const values = defaultValues()
        values.exposure = 35
        values.highlights = -18
        values.temperature = 24
        values.vibrance = -7
        inspector.adjustmentValues = values
        compare(findChild(inspector, "adjustment-exposure").value, 35)
        compare(findChild(inspector, "adjustment-highlights").value, -18)
        compare(findChild(inspector, "adjustment-temperature").value, 24)
        compare(findChild(inspector, "adjustment-vibrance").value, -7)
    }

    function test_hslChannelSelectionChangesKeysAndValues() {
        inspector.adjustTab = 1
        const hsl = findChild(inspector, "hsl-controls")
        verify(hsl !== null)

        mouseClick(findChild(inspector, "hsl-channel-blue"))
        compare(hsl.channel, "blue")
        const blueSaturation = findChild(inspector, "adjustment-hsl-blue-saturation")
        verify(blueSaturation !== null)
        compare(blueSaturation.from, -100)
        compare(blueSaturation.to, 100)
        blueSaturation.forceActiveFocus()
        keyClick(Qt.Key_Right)
        compare(started.count, 1)
        compare(finished.count, 1)
        compare(finished.signalArguments[0][0], "hsl.blue.saturation")

        started.clear(); preview.clear(); finished.clear()
        mouseClick(findChild(inspector, "hsl-channel-red"))
        compare(hsl.channel, "red")
        const redHue = findChild(inspector, "adjustment-hsl-red-hue")
        redHue.forceActiveFocus()
        keyClick(Qt.Key_Right)
        compare(finished.signalArguments[0][0], "hsl.red.hue")

        const values = defaultValues()
        values["hsl.green.hue"] = 42
        values["hsl.green.saturation"] = -16
        values["hsl.green.luminance"] = 9
        inspector.adjustmentValues = values
        mouseClick(findChild(inspector, "hsl-channel-green"))
        compare(findChild(inspector, "adjustment-hsl-green-hue").value, 42)
        compare(findChild(inspector, "adjustment-hsl-green-saturation").value, -16)
        compare(findChild(inspector, "adjustment-hsl-green-luminance").value, 9)
    }

    function test_hslResetEmitsCompleteTransactionForCurrentColour() {
        inspector.adjustTab = 1
        mouseClick(findChild(inspector, "hsl-channel-purple"))
        const values = defaultValues()
        values["hsl.purple.hue"] = 30
        values["hsl.purple.saturation"] = 40
        values["hsl.purple.luminance"] = -20
        inspector.adjustmentValues = values

        started.clear(); preview.clear(); finished.clear()
        mouseClick(findChild(inspector, "hsl-reset"))
        compare(started.count, 3)
        compare(finished.count, 3)
        const keys = finished.signalArguments.map(function(args) { return args[0] })
        verify(keys.indexOf("hsl.purple.hue") >= 0)
        verify(keys.indexOf("hsl.purple.saturation") >= 0)
        verify(keys.indexOf("hsl.purple.luminance") >= 0)
        for (let i = 0; i < finished.signalArguments.length; ++i)
            compare(finished.signalArguments[i][1], 0)
    }

    function test_curvePointDragIsSingleTransaction() {
        inspector.adjustTab = 2
        const editor = findChild(inspector, "curve-editor")
        verify(editor !== null)
        compare(editor.points.length, 5)
        compare(editor.points[1], 25)

        const point = findChild(inspector, "curve-point-1")
        verify(point !== null)
        mousePress(point, point.width / 2, point.height / 2)
        mouseMove(point, point.width / 2, point.height / 2 - 24)
        mouseRelease(point, point.width / 2, point.height / 2 - 24)

        compare(started.count, 1)
        compare(preview.count, 1)
        compare(finished.count, 1)
        compare(started.signalArguments[0][0], "curve.RGB.1")
        compare(finished.signalArguments[0][0], "curve.RGB.1")
        verify(finished.signalArguments[0][1] > 25)
        compare(editor.points[1], finished.signalArguments[0][1])
    }

    function test_curveChannelSelectionChangesKey() {
        inspector.adjustTab = 2
        mouseClick(findChild(inspector, "curve-channel-G"))
        const editor = findChild(inspector, "curve-editor")
        compare(editor.channel, "G")
        compare(editor.points[2], 50)

        const point = findChild(inspector, "curve-point-2")
        mousePress(point, point.width / 2, point.height / 2)
        mouseMove(point, point.width / 2, point.height / 2 - 20)
        mouseRelease(point, point.width / 2, point.height / 2 - 20)
        compare(started.count, 1)
        compare(finished.count, 1)
        compare(finished.signalArguments[0][0], "curve.G.2")
    }

    function test_curvePresetsCommitAllFivePoints() {
        inspector.adjustTab = 2
        const editor = findChild(inspector, "curve-editor")

        mouseClick(findChild(inspector, "curve-preset-contrast"))
        compare(started.count, 5)
        compare(preview.count, 5)
        compare(finished.count, 5)
        compare(editor.points[0], 0)
        compare(editor.points[1], 17)
        compare(editor.points[2], 50)
        compare(editor.points[3], 83)
        compare(editor.points[4], 100)
        const keys = finished.signalArguments.map(function(args) { return args[0] })
        for (let i = 0; i < 5; ++i)
            verify(keys.indexOf("curve.RGB." + i) >= 0)

        started.clear(); preview.clear(); finished.clear()
        mouseClick(findChild(inspector, "curve-preset-linear"))
        compare(started.count, 5)
        compare(finished.count, 5)
        compare(editor.points[0], 0)
        compare(editor.points[1], 25)
        compare(editor.points[2], 50)
        compare(editor.points[3], 75)
        compare(editor.points[4], 100)
    }

    function test_curveValuesFollowController() {
        inspector.adjustTab = 2
        const editor = findChild(inspector, "curve-editor")
        const values = defaultValues()
        values["curve.RGB.0"] = 5
        values["curve.RGB.1"] = 20
        values["curve.RGB.4"] = 90
        inspector.adjustmentValues = values
        compare(editor.points[0], 5)
        compare(editor.points[1], 20)
        compare(editor.points[2], 50)
        compare(editor.points[4], 90)
        compare(findChild(inspector, "adjustment-curve-RGB-4").value, 90)
    }

    function test_curveNumericFallbackEmitsPointKey() {
        inspector.adjustTab = 2
        const slider = findChild(inspector, "adjustment-curve-RGB-0")
        verify(slider !== null)
        compare(slider.from, 0)
        compare(slider.to, 100)
        compare(slider.value, 0)
        slider.forceActiveFocus()
        keyClick(Qt.Key_Up)
        compare(started.count, 1)
        compare(finished.count, 1)
        compare(finished.signalArguments[0][0], "curve.RGB.0")
        compare(finished.signalArguments[0][1], 1)
    }

    function test_gradeZoneSelectionKeysAndRanges() {
        inspector.adjustTab = 3
        const shadowsHue = findChild(inspector, "adjustment-grade-shadows-hue")
        compare(shadowsHue.from, 0)
        compare(shadowsHue.to, 360)

        mouseClick(findChild(inspector, "grade-zone-highlights"))
        compare(findChild(inspector, "grade-controls").zone, "highlights")
        const hue = findChild(inspector, "adjustment-grade-highlights-hue")
        const saturation = findChild(inspector, "adjustment-grade-highlights-saturation")
        const luminance = findChild(inspector, "adjustment-grade-highlights-luminance")
        verify(hue !== null)
        verify(saturation !== null)
        verify(luminance !== null)
        compare(saturation.from, 0)
        compare(saturation.to, 100)
        compare(luminance.from, -100)
        compare(luminance.to, 100)

        hue.forceActiveFocus()
        keyClick(Qt.Key_Right)
        compare(started.count, 1)
        compare(finished.count, 1)
        compare(finished.signalArguments[0][0], "grade.highlights.hue")
        compare(finished.signalArguments[0][1], 1)

        const values = defaultValues()
        values["grade.highlights.hue"] = 180
        values["grade.highlights.saturation"] = 60
        values["grade.highlights.luminance"] = -20
        inspector.adjustmentValues = values
        compare(hue.value, 180)
        compare(saturation.value, 60)
        compare(luminance.value, -20)
        verify(findChild(inspector, "grade-swatch").color !== undefined)
    }

    function test_gradeBlendingBalanceAndReset() {
        inspector.adjustTab = 3
        const blending = findChild(inspector, "adjustment-grade-blending")
        const balance = findChild(inspector, "adjustment-grade-balance")
        verify(blending !== null)
        verify(balance !== null)
        compare(blending.from, 0)
        compare(blending.to, 100)
        compare(blending.value, 50)
        compare(balance.from, -100)
        compare(balance.to, 100)

        blending.forceActiveFocus()
        keyClick(Qt.Key_Right)
        compare(finished.signalArguments[0][0], "grade.blending")
        compare(finished.signalArguments[0][1], 51)

        started.clear(); preview.clear(); finished.clear()
        balance.forceActiveFocus()
        keyClick(Qt.Key_Left)
        compare(finished.signalArguments[0][0], "grade.balance")
        compare(finished.signalArguments[0][1], -1)

        mouseClick(findChild(inspector, "grade-zone-midtones"))
        const values = defaultValues()
        values["grade.midtones.hue"] = 90
        values["grade.midtones.saturation"] = 20
        values["grade.midtones.luminance"] = 10
        inspector.adjustmentValues = values

        started.clear(); preview.clear(); finished.clear()
        const resetButton = findChild(inspector, "grade-reset")
        verify(resetButton !== null)
        resetButton.forceActiveFocus()
        keyClick(Qt.Key_Space)
        compare(started.count, 3)
        compare(finished.count, 3)
        const keys = finished.signalArguments.map(function(args) { return args[0] })
        verify(keys.indexOf("grade.midtones.hue") >= 0)
        verify(keys.indexOf("grade.midtones.saturation") >= 0)
        verify(keys.indexOf("grade.midtones.luminance") >= 0)
        for (let i = 0; i < finished.signalArguments.length; ++i)
            compare(finished.signalArguments[i][1], 0)
    }

    function test_detailEffectKeysAndRanges() {
        inspector.adjustTab = 4
        const entries = [
            { key: "texture", from: 0, expected: 1 },
            { key: "clarity", from: 0, expected: 1 },
            { key: "dehaze", from: 0, expected: 1 },
            { key: "sharpen", from: 0, expected: 1 },
            { key: "noise", from: 0, expected: 1 },
            { key: "colorNoise", from: 0, expected: 1 },
            { key: "vignette", from: -100, expected: 1 },
            { key: "feather", from: 0, expected: 51 },
            { key: "grain", from: 0, expected: 1 },
            { key: "fade", from: 0, expected: 1 }
        ]
        for (let i = 0; i < entries.length; ++i) {
            started.clear(); preview.clear(); finished.clear()
            const slider = findChild(inspector, "adjustment-" + entries[i].key)
            verify(slider !== null)
            compare(slider.from, entries[i].from)
            compare(slider.to, 100)
            slider.forceActiveFocus()
            keyClick(Qt.Key_Right)
            compare(started.count, 1)
            compare(preview.count, 1)
            compare(finished.count, 1)
            compare(finished.signalArguments[0][0], entries[i].key)
            compare(finished.signalArguments[0][1], entries[i].expected)
        }
    }

    function test_detailEffectValuesFollowController() {
        inspector.adjustTab = 4
        const values = defaultValues()
        values.texture = 33
        values.clarity = 44
        values.dehaze = 55
        values.sharpen = 66
        values.noise = 11
        values.colorNoise = 22
        values.vignette = -33
        values.feather = 77
        values.grain = 88
        values.fade = 99
        inspector.adjustmentValues = values
        const keys = ["texture", "clarity", "dehaze", "sharpen", "noise",
                      "colorNoise", "vignette", "feather", "grain", "fade"]
        for (let i = 0; i < keys.length; ++i)
            compare(findChild(inspector, "adjustment-" + keys[i]).value, values[keys[i]])
    }

    function test_allAdjustTabsDisableWithoutImage() {
        inspector.adjustmentsEnabled = false
        const representatives = [
            "adjustment-exposure", "adjustment-hsl-red-hue",
            "adjustment-curve-RGB-0", "adjustment-grade-shadows-hue",
            "adjustment-texture"
        ]
        for (let tab = 0; tab < representatives.length; ++tab) {
            inspector.adjustTab = tab
            const slider = findChild(inspector, representatives[tab])
            verify(slider !== null)
            verify(!slider.enabled)
        }
        verify(!findChild(inspector, "adjustment-reset").enabled)
        verify(!findChild(inspector, "hsl-reset").enabled)
        verify(!findChild(inspector, "curve-preset-linear").enabled)
        verify(!findChild(inspector, "grade-reset").enabled)
        inspector.adjustTab = 1
        verify(!findChild(inspector, "hsl-channel-blue").enabled)
    }
}
