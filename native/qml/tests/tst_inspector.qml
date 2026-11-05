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

    function init() {
        started.clear(); preview.clear(); finished.clear(); reset.clear()
        filterSelected.clear(); filterStarted.clear(); filterPreview.clear(); filterFinished.clear()
        inspector.currentTab = 0
        previewNotification.enabled = false
        inspector.adjustmentValues = ({ exposure: 0, brightness: 0, contrast: 0, saturation: 0 })
        inspector.adjustmentsEnabled = true
        inspector.filtersEnabled = true
        inspector.filterPreset = "none"
        inspector.filterIntensity = 100
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
        for (let i = 0; i < 12; ++i)
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
}
