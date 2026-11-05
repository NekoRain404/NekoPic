.pragma library

/*!
    FontCatalog — builds the text panel's font-family catalog.

    Qt.fontFamilies() is already unique on most platforms, but the catalog is
    deduplicated case-insensitively and sorted before the preferred families
    are moved to the front. The empty entry (system default) is always first.
*/

var preferredFamilies = [
    "Noto Sans CJK SC", "Noto Serif CJK SC",
    "Source Han Sans SC", "Source Han Serif SC",
    "Noto Sans CJK TC", "Noto Serif CJK TC",
    "Noto Sans CJK JP", "Noto Serif CJK JP",
    "Noto Sans CJK KR", "Noto Serif CJK KR",
    "Noto Sans SC", "Noto Serif SC",
    "Noto Sans TC", "Noto Serif TC",
    "WenQuanYi Micro Hei", "WenQuanYi Zen Hei",
    "Microsoft YaHei", "PingFang SC", "Hiragino Sans GB",
    "Sarasa UI SC", "Sarasa Mono SC",
    "Noto Sans", "Noto Serif",
    "DejaVu Sans", "DejaVu Serif",
    "Liberation Sans", "Liberation Serif",
    "sans-serif", "serif", "monospace"
]

/*! Used only when the runtime cannot enumerate fonts at all. */
var curatedFamilies = [
    "Noto Sans CJK SC", "Noto Serif CJK SC", "Source Han Sans SC",
    "Source Han Serif SC", "DejaVu Sans", "sans-serif"
]

function build(families, defaultLabel) {
    var seen = Object.create(null)
    var unique = []
    for (var i = 0; i < families.length; ++i) {
        var raw = families[i]
        var name = String(raw === undefined || raw === null ? "" : raw).trim()
        if (name.length === 0)
            continue
        var key = name.toLowerCase()
        if (seen[key])
            continue
        seen[key] = true
        unique.push(name)
    }
    unique.sort(function(a, b) { return a.localeCompare(b) })

    var byKey = Object.create(null)
    for (var j = 0; j < unique.length; ++j)
        byKey[unique[j].toLowerCase()] = unique[j]

    var items = [{ label: defaultLabel, value: "" }]
    var added = Object.create(null)
    for (var p = 0; p < preferredFamilies.length; ++p) {
        var preferredKey = preferredFamilies[p].toLowerCase()
        var actual = byKey[preferredKey]
        if (actual === undefined || added[preferredKey])
            continue
        added[preferredKey] = true
        items.push({ label: actual, value: actual })
    }
    for (var k = 0; k < unique.length; ++k) {
        var familyKey = unique[k].toLowerCase()
        if (added[familyKey])
            continue
        added[familyKey] = true
        items.push({ label: unique[k], value: unique[k] })
    }
    return items
}
