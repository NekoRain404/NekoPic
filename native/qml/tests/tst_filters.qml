import QtQuick
import QtTest
import "../filters"

TestCase {
    name: "FiltersPanel"
    when: windowShown
    visible: true
    width: 340
    height: 760

    FiltersPanel {
        id: panel
        width: 292
        currentPreset: "none"
        intensity: 100
        presetsEnabled: true
    }

    SignalSpy { id: selected; target: panel; signalName: "filterSelected" }
    SignalSpy { id: intensityStarted; target: panel; signalName: "intensityStarted" }
    SignalSpy { id: intensityPreview; target: panel; signalName: "intensityPreview" }
    SignalSpy { id: intensityFinished; target: panel; signalName: "intensityFinished" }

    readonly property var ids: [
        "none", "fresh", "vivid", "warm", "cool", "film", "faded",
        "vintage", "sunset", "soft", "cream", "mono", "silver"
    ]

    function init() {
        selected.clear()
        intensityStarted.clear()
        intensityPreview.clear()
        intensityFinished.clear()
        panel.currentPreset = "none"
        panel.intensity = 100
        panel.presetsEnabled = true
        panel.intensityEnabled = true
        panel.favourites = []
        panel.activeCategory = "all"
        panel.query = ""
        wait(0)
    }

    function tile(id) {
        return findChild(panel, "filter-" + id)
    }

    function test_allRegistryTilesAndCategoriesExist() {
        for (let i = 0; i < ids.length; ++i) {
            const button = tile(ids[i])
            verify(button !== null, "missing tile " + ids[i])
            verify(button.text.length > 0, "missing label " + ids[i])
            verify(findChild(panel, "filter-preview-" + ids[i]) !== null,
                   "missing preview " + ids[i])
        }
        const categories = ["all", "natural", "film", "portrait", "atmosphere", "mono", "favourites"]
        for (let i = 0; i < categories.length; ++i)
            verify(findChild(panel, "filter-category-" + categories[i]) !== null,
                   "missing category " + categories[i])
        compare(panel.visibleCount, 13)
    }

    function test_tileClickEmitsEveryRegistryId() {
        for (let i = 0; i < ids.length; ++i) {
            selected.clear()
            const button = tile(ids[i])
            verify(button !== null)
            mouseClick(button)
            compare(selected.count, 1, "no signal for " + ids[i])
            compare(selected.signalArguments[0][0], ids[i])
        }
    }

    function test_searchFiltersByLabelAndId() {
        const field = findChild(panel, "filter-search")
        verify(field !== null)
        field.text = "sil"
        tryCompare(panel, "visibleCount", 1)
        verify(tile("silver").visible)
        verify(!tile("warm").visible)

        panel.query = "VINT"
        tryCompare(panel, "visibleCount", 1)
        verify(tile("vintage").visible)
        compare(field.text, "VINT")

        panel.query = "original"
        tryCompare(panel, "visibleCount", 1)
        verify(tile("none").visible)
    }

    function test_searchEmptyState() {
        panel.query = "no-such-look"
        tryCompare(panel, "visibleCount", 0)
        verify(findChild(panel, "filter-empty").visible)
        for (let i = 0; i < ids.length; ++i)
            verify(!tile(ids[i]).visible)

        panel.query = ""
        tryCompare(panel, "visibleCount", 13)
        verify(!findChild(panel, "filter-empty").visible)
    }

    function test_categoryChipsFilterTiles() {
        const expected = {
            natural: 4, film: 3, atmosphere: 1, portrait: 2, mono: 2, all: 13
        }
        const order = ["natural", "film", "atmosphere", "portrait", "mono", "all"]
        for (let i = 0; i < order.length; ++i) {
            const category = order[i]
            mouseClick(findChild(panel, "filter-category-" + category))
            compare(panel.activeCategory, category)
            compare(panel.visibleCount, expected[category], category + " count")
        }
        verify(tile("silver").visible)
        verify(tile("fresh").visible)
    }

    function test_favouritesToggleAndCategory() {
        const star = findChild(panel, "filter-favorite-warm")
        verify(star !== null)
        compare(star.text, "☆")
        mouseClick(star)
        compare(panel.favourites.length, 1)
        compare(panel.favourites[0], "warm")
        compare(star.text, "★")

        mouseClick(findChild(panel, "filter-category-favourites"))
        compare(panel.activeCategory, "favourites")
        compare(panel.visibleCount, 1)
        verify(tile("warm").visible)
        verify(!tile("vivid").visible)

        // Toggling off inside the favourites category empties the grid.
        mouseClick(star)
        compare(panel.favourites.length, 0)
        compare(panel.visibleCount, 0)
        verify(findChild(panel, "filter-empty").visible)

        // Original is not a favouritable look, matching the H5 prototype.
        const originalStar = findChild(panel, "filter-favorite-none")
        verify(originalStar !== null)
        verify(!originalStar.visible)
    }

    function test_strengthSliderTracksControllerAndGesture() {
        panel.currentPreset = "warm"
        panel.intensity = 42
        const slider = findChild(panel, "filter-intensity")
        compare(slider.value, 42)
        verify(slider.enabled)

        slider.forceActiveFocus()
        keyClick(Qt.Key_Right)
        compare(intensityStarted.count, 1)
        compare(intensityPreview.count, 1)
        compare(intensityFinished.count, 1)
        compare(intensityPreview.signalArguments[0][0], 43)
        compare(intensityFinished.signalArguments[0][0], 43)

        intensityStarted.clear()
        intensityPreview.clear()
        intensityFinished.clear()
        mousePress(slider, slider.width * 0.25, slider.height / 2)
        mouseMove(slider, slider.width * 0.7, slider.height / 2)
        mouseRelease(slider, slider.width * 0.7, slider.height / 2)
        compare(intensityStarted.count, 1)
        verify(intensityPreview.count > 0)
        compare(intensityFinished.count, 1)
    }

    function test_strengthDisabledForOriginal() {
        panel.currentPreset = "none"
        verify(!findChild(panel, "filter-intensity").enabled)
        panel.currentPreset = "silver"
        verify(findChild(panel, "filter-intensity").enabled)
    }

    function test_presetsDisabledWhileStrengthMayRemain() {
        panel.presetsEnabled = false
        panel.intensityEnabled = true
        panel.currentPreset = "film"
        verify(!tile("film").enabled)
        verify(findChild(panel, "filter-intensity").enabled)

        panel.intensityEnabled = false
        verify(!findChild(panel, "filter-intensity").enabled)
    }

    function test_currentLookLabelFollowsPreset() {
        const label = findChild(panel, "filter-current-look")
        compare(label.text, "Original")
        panel.currentPreset = "sunset"
        compare(label.text, "Sunset")
    }

    function test_gridFitsNarrowPanelWidths() {
        const widths = [292, 260]
        for (let w = 0; w < widths.length; ++w) {
            panel.width = widths[w]
            wait(0)
            const grid = findChild(panel, "filter-grid")
            verify(grid !== null)
            verify(grid.columns <= 3, "unexpected column count " + grid.columns)
            verify(grid.width <= panel.width + 0.5,
                   "grid " + grid.width + " exceeds panel " + panel.width)
            for (let i = 0; i < ids.length; ++i) {
                const button = tile(ids[i])
                if (!button.visible)
                    continue
                const point = button.mapToItem(panel, 0, 0)
                verify(point.x >= -0.5, ids[i] + " overflows the left edge")
                verify(point.x + button.width <= panel.width + 0.5,
                       ids[i] + " overflows the right edge at " + panel.width + "px")
            }
            const search = findChild(panel, "filter-search")
            verify(search.mapToItem(panel, 0, 0).x + search.width <= panel.width + 0.5,
                   "search field overflows at " + panel.width + "px")
            const slider = findChild(panel, "filter-intensity")
            verify(slider.mapToItem(panel, 0, 0).x + slider.width <= panel.width + 0.5,
                   "strength slider overflows at " + panel.width + "px")
        }
        panel.width = 292
    }
}
