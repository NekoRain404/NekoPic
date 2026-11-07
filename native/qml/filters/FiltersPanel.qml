pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../UI"

/*!
    FiltersPanel — the complete Filters workspace.

    It mirrors the stable C++ preset registry (none + 12 looks) with live
    per-photo previews, search, category chips and session-local favourites.
    The Inspector binds its public preset/intensity properties and relays the
    signals so Main.qml and DocumentController keep their existing contract.
*/
ColumnLayout {
    id: root

    property string currentPreset: "none"
    property real intensity: 100
    property bool presetsEnabled: false
    property bool intensityEnabled: presetsEnabled
    property bool previewsAvailable: false
    property double previewRevision: 0
    /*! Session-local favourite ids. The H5 prototype keeps these in memory. */
    property var favourites: []
    property string activeCategory: "all"
    property string query: ""

    signal filterSelected(string preset)
    signal intensityStarted()
    signal intensityPreview(real value)
    signal intensityFinished(real value)

    /*! Mirrors native/src/core/filterpresets.cpp. Keep ids and categories in
        sync with that registry; labels are translated here at the UI boundary. */
    readonly property var presets: [
        { id: "none", label: qsTr("Original"), category: "none" },
        { id: "fresh", label: qsTr("Fresh"), category: "natural" },
        { id: "vivid", label: qsTr("Vivid"), category: "natural" },
        { id: "warm", label: qsTr("Warm"), category: "natural" },
        { id: "cool", label: qsTr("Cool"), category: "natural" },
        { id: "film", label: qsTr("Film"), category: "film" },
        { id: "faded", label: qsTr("Faded"), category: "film" },
        { id: "vintage", label: qsTr("Vintage"), category: "film" },
        { id: "sunset", label: qsTr("Sunset"), category: "atmosphere" },
        { id: "soft", label: qsTr("Soft"), category: "portrait" },
        { id: "cream", label: qsTr("Cream"), category: "portrait" },
        { id: "mono", label: qsTr("Mono"), category: "mono" },
        { id: "silver", label: qsTr("Silver"), category: "mono" }
    ]

    readonly property var categories: [
        { id: "all", label: qsTr("All") },
        { id: "natural", label: qsTr("Natural") },
        { id: "film", label: qsTr("Film") },
        { id: "portrait", label: qsTr("Portrait") },
        { id: "atmosphere", label: qsTr("Atmosphere") },
        { id: "mono", label: qsTr("Mono") },
        { id: "favourites", label: qsTr("Favourites") }
    ]

    readonly property int visibleCount: root.countVisible()

    Layout.fillWidth: true
    spacing: Theme.spacingMd

    function presetLabel(id) {
        for (let i = 0; i < root.presets.length; ++i) {
            if (root.presets[i].id === id)
                return root.presets[i].label
        }
        return qsTr("Original")
    }

    function isFavourite(id) {
        return root.favourites.indexOf(id) >= 0
    }

    function categoryMatches(preset) {
        if (root.activeCategory === "all")
            return true
        if (root.activeCategory === "favourites")
            return root.isFavourite(preset.id)
        return preset.category === root.activeCategory
    }

    function searchMatches(preset) {
        const term = root.query.trim().toLowerCase()
        if (term.length === 0)
            return true
        return preset.label.toLowerCase().indexOf(term) >= 0
            || preset.id.indexOf(term) >= 0
    }

    function presetVisible(preset) {
        return root.categoryMatches(preset) && root.searchMatches(preset)
    }

    function countVisible() {
        let count = 0
        for (let i = 0; i < root.presets.length; ++i) {
            if (root.presetVisible(root.presets[i]))
                ++count
        }
        return count
    }

    function toggleFavourite(id) {
        const next = root.favourites.slice()
        const index = next.indexOf(id)
        if (index >= 0)
            next.splice(index, 1)
        else
            next.push(id)
        root.favourites = next
    }

    function setCategory(id) {
        if (root.activeCategory !== id)
            root.activeCategory = id
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacingSm

        Label {
            text: qsTr("Current look")
            color: Theme.textSecondary
            font.pixelSize: Theme.fontCaption
        }
        Item { Layout.fillWidth: true }
        Label {
            objectName: "filter-current-look"
            text: root.currentPreset === "none" ? qsTr("Original")
                                                : root.presetLabel(root.currentPreset)
            color: Theme.textPrimary
            font.pixelSize: Theme.fontSmall
            font.weight: Theme.fontWeightMedium
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacingSm

        Label {
            text: qsTr("Strength")
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSmall
        }
        Item { Layout.fillWidth: true }

        Rectangle {
            implicitWidth: Math.max(42, intensityValue.implicitWidth + Theme.spacingMd)
            implicitHeight: 20
            radius: Theme.radiusXs
            color: Theme.background
            border.width: Theme.borderWidth
            border.color: Theme.separator

            Label {
                id: intensityValue
                objectName: "filter-intensity-value"
                anchors.centerIn: parent
                text: Math.round(intensitySlider.value) + "%"
                color: Theme.textSecondary
                font.pixelSize: Theme.fontCaption
                font.weight: Theme.fontWeightMedium
            }
        }
    }

    NekoSlider {
        id: intensitySlider
        objectName: "filter-intensity"
        Layout.fillWidth: true
        from: 0
        to: 100
        stepSize: 1
        defaultValue: 100
        enabled: root.intensityEnabled && root.currentPreset !== "none"
        accessibleName: qsTr("Filter strength")
        onBegin: root.intensityStarted()
        onPreview: function(value) { root.intensityPreview(value) }
        onFinish: function(value) { root.intensityFinished(value) }
        Component.onCompleted: value = root.intensity
        Connections {
            target: root
            function onIntensityChanged() {
                if (!intensitySlider.dragging)
                    intensitySlider.value = root.intensity
            }
        }
    }

    TextField {
        id: searchField
        objectName: "filter-search"
        Layout.fillWidth: true
        implicitHeight: Theme.controlHeightSm
        placeholderText: qsTr("Search looks")
        placeholderTextColor: Theme.textTertiary
        color: Theme.textPrimary
        selectionColor: Theme.selection
        selectedTextColor: Theme.textPrimary
        font.pixelSize: Theme.fontSmall
        leftPadding: Theme.spacingSm
        rightPadding: Theme.spacingSm
        verticalAlignment: TextInput.AlignVCenter
        selectByMouse: true

        Accessible.name: qsTr("Search looks")

        onTextChanged: {
            if (root.query !== text)
                root.query = text
        }

        Connections {
            target: root
            function onQueryChanged() {
                if (searchField.text !== root.query)
                    searchField.text = root.query
            }
        }

        background: Rectangle {
            radius: Theme.radiusSm
            color: Theme.background
            border.width: searchField.activeFocus ? Theme.focusRingWidth : Theme.borderWidth
            border.color: searchField.activeFocus ? Theme.focusRing
                        : searchField.hovered ? Theme.textTertiary : Theme.border
            Behavior on border.color {
                ColorAnimation {
                    duration: Motion.duration(Motion.fast)
                    easing.type: Motion.decelerateEasing
                }
            }
        }
    }

    Flow {
        Layout.fillWidth: true
        Layout.preferredHeight: childrenRect.height
        spacing: Theme.spacingXs

        Repeater {
            model: root.categories

            delegate: FilterCategoryChip {
                required property var modelData
                objectName: "filter-category-" + modelData.id
                text: modelData.label
                chipId: modelData.id
                selected: root.activeCategory === modelData.id
                onClicked: root.setCategory(modelData.id)
            }
        }
    }

    Label {
        objectName: "filter-result-count"
        Layout.fillWidth: true
        text: qsTr("%n look(s)", "", root.visibleCount)
        color: Theme.textTertiary
        font.pixelSize: Theme.fontCaption
        Accessible.name: text
    }

    GridLayout {
        objectName: "filter-grid"
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        Layout.maximumWidth: root.width
        // Three columns keep each preview comfortably above the 64 px tile
        // minimum at both 260 px and 292 px panel widths. Tiles must be
        // allowed to shrink below their implicit width; otherwise the grid
        // reports a 4 × 120 px minimum and clips the right edge.
        columns: root.width > 0 && root.width < 232 ? 2 : 3
        rowSpacing: Theme.spacingSm
        columnSpacing: Theme.spacingSm

        Repeater {
            model: root.presets

            delegate: FilterTile {
                required property var modelData
                visible: root.presetVisible(modelData)
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.preferredWidth: 0
                Layout.preferredHeight: 68
                presetId: modelData.id
                label: modelData.label
                selected: root.currentPreset === modelData.id
                favourite: root.isFavourite(modelData.id)
                previewsAvailable: root.previewsAvailable
                previewRevision: root.previewRevision
                controlsEnabled: root.presetsEnabled
                onActivated: root.filterSelected(modelData.id)
                onFavouriteToggled: root.toggleFavourite(modelData.id)
            }
        }
    }

    Item {
        objectName: "filter-empty"
        Layout.fillWidth: true
        Layout.preferredHeight: 132
        visible: root.visibleCount === 0

        Accessible.role: Accessible.StaticText
        Accessible.name: emptyLabel.text

        Column {
            anchors.centerIn: parent
            width: Math.min(parent.width, 220)
            spacing: Theme.spacingSm

            NekoIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Theme.iconSizeLg
                height: Theme.iconSizeLg
                name: "filters"
                color: Theme.textTertiary
                opacity: 0.7
            }

            Label {
                id: emptyLabel
                width: parent.width
                text: qsTr("No looks match. Try another category or search.")
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                color: Theme.textTertiary
                font.pixelSize: Theme.fontSmall
                lineHeight: Theme.lineHeightNormal
            }
        }
    }

}
