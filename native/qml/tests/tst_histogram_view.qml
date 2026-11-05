import QtQuick
import QtTest
import "../components"

TestCase {
    id: testCase
    name: "HistogramView"
    when: windowShown
    visible: true
    width: 300
    height: 120

    Component {
        id: histogramComponent
        HistogramView { width: 240; height: 64 }
    }

    function test_acceptsBinsAndComputesPeak() {
        const view = createTemporaryObject(histogramComponent, testCase)
        verify(view !== null)
        compare(view.peak, 0)
        const bins = []
        for (let i = 0; i < 256; ++i) bins.push(i === 128 ? 1000 : 0)
        view.bins = bins
        compare(view.peak, 1000)
        wait(0)
    }

    function test_emptyDataDoesNotCrash() {
        const view = createTemporaryObject(histogramComponent, testCase)
        view.bins = []
        compare(view.peak, 0)
        view.bins = null
        compare(view.peak, 0)
    }
}
