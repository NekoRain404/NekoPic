#pragma once

#include <QString>
#include <QStringList>

namespace NekoPic::Filters {

struct Preset {
    QString id;
    QString label;    // English source; translate at the UI boundary.
    QString category; // none/natural/film/portrait/atmosphere/mono
};

// Stable preset ids are the only values that may cross into the document or
// be persisted. Display labels and categories are UI metadata.
QStringList presetIds();
QStringList presetCategories();
bool isValidPreset(const QString &id);
Preset preset(const QString &id);
QString defaultPreset();

} // namespace NekoPic::Filters
