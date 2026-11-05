#include "filterpresets.h"

#include <QHash>

namespace NekoPic::Filters {
namespace {

const QList<Preset> &allPresets()
{
    static const QList<Preset> presets{
        {QStringLiteral("none"), QStringLiteral("Original"), QStringLiteral("none")},
        {QStringLiteral("fresh"), QStringLiteral("Fresh"), QStringLiteral("natural")},
        {QStringLiteral("vivid"), QStringLiteral("Vivid"), QStringLiteral("natural")},
        {QStringLiteral("warm"), QStringLiteral("Warm"), QStringLiteral("natural")},
        {QStringLiteral("cool"), QStringLiteral("Cool"), QStringLiteral("natural")},
        {QStringLiteral("film"), QStringLiteral("Film"), QStringLiteral("film")},
        {QStringLiteral("faded"), QStringLiteral("Faded"), QStringLiteral("film")},
        {QStringLiteral("vintage"), QStringLiteral("Vintage"), QStringLiteral("film")},
        {QStringLiteral("sunset"), QStringLiteral("Sunset"), QStringLiteral("atmosphere")},
        {QStringLiteral("soft"), QStringLiteral("Soft"), QStringLiteral("portrait")},
        {QStringLiteral("cream"), QStringLiteral("Cream"), QStringLiteral("portrait")},
        {QStringLiteral("mono"), QStringLiteral("Mono"), QStringLiteral("mono")},
        {QStringLiteral("silver"), QStringLiteral("Silver"), QStringLiteral("mono")},
    };
    return presets;
}

} // namespace

QStringList presetIds()
{
    QStringList ids;
    for (const auto &item : allPresets()) ids.append(item.id);
    return ids;
}

QStringList presetCategories()
{
    return {QStringLiteral("all"), QStringLiteral("natural"), QStringLiteral("film"),
            QStringLiteral("portrait"), QStringLiteral("atmosphere"),
            QStringLiteral("mono")};
}

bool isValidPreset(const QString &id)
{
    for (const auto &item : allPresets()) {
        if (item.id == id) return true;
    }
    return false;
}

Preset preset(const QString &id)
{
    for (const auto &item : allPresets()) {
        if (item.id == id) return item;
    }
    return allPresets().first();
}

QString defaultPreset() { return QStringLiteral("none"); }

} // namespace NekoPic::Filters
