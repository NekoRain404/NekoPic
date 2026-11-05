#include "colorpipeline_internal.h"

#include <QHash>
#include <QVariantMap>

#include <limits>
#include <utility>
#include <vector>

namespace NekoPic::Adjustments {

using Internal::isActivePreset;
using Internal::isLinearCurve;
using Internal::parsePreset;
using Internal::sanitized;

namespace {

// ---------------------------------------------------------------------------
// Key registry
//
// Keys, UI ranges and stored/UI scaling are the stable contract consumed by
// the QML panel; keep them byte-for-byte compatible with the original table.
// ---------------------------------------------------------------------------

enum class Field
{
    Scalar,
    HslHue,
    HslSaturation,
    HslLuminance,
    CurvePoint,
    GradeHue,
    GradeSaturation,
    GradeLuminance,
};

struct KeyInfo
{
    Field field = Field::Scalar;
    int index = 0;
    int sub = 0;
    double uiMin = 0.0;
    double uiMax = 0.0;
    double storedPerUi = 1.0;
    double uiPerStored = 1.0;
    double Parameters::* member = nullptr;
};

struct Registry
{
    QStringList keys;
    QHash<QString, int> lookup;
    std::vector<KeyInfo> infos;
};

Registry buildRegistry()
{
    Registry registry;

    const auto add = [&](const QString& key, Field field, int index, int sub, double uiMin,
                         double uiMax, double storedPerUi, double uiPerStored,
                         double Parameters::* member) {
        const int position = static_cast<int>(registry.infos.size());
        registry.infos.push_back(
            {field, index, sub, uiMin, uiMax, storedPerUi, uiPerStored, member});
        registry.keys.append(key);
        registry.lookup.insert(key, position);
    };

    const auto addScalar = [&](const char* key, double uiMin, double uiMax, double storedPerUi,
                               double uiPerStored, double Parameters::* member) {
        add(QString::fromLatin1(key), Field::Scalar, 0, 0, uiMin, uiMax, storedPerUi, uiPerStored,
            member);
    };

    // Basic controls.
    addScalar("exposure", -100.0, 100.0, 4.0 / 100.0, 25.0, &Parameters::exposure);
    addScalar("brightness", -100.0, 100.0, 0.01, 100.0, &Parameters::brightness);
    addScalar("contrast", -100.0, 100.0, 0.01, 100.0, &Parameters::contrast);
    addScalar("saturation", -100.0, 100.0, 0.01, 100.0, &Parameters::saturation);
    addScalar("highlights", -100.0, 100.0, 0.01, 100.0, &Parameters::highlights);
    addScalar("shadows", -100.0, 100.0, 0.01, 100.0, &Parameters::shadows);
    addScalar("whites", -100.0, 100.0, 0.01, 100.0, &Parameters::whites);
    addScalar("blacks", -100.0, 100.0, 0.01, 100.0, &Parameters::blacks);
    addScalar("temperature", -100.0, 100.0, 0.01, 100.0, &Parameters::temperature);
    addScalar("tint", -100.0, 100.0, 0.01, 100.0, &Parameters::tint);
    addScalar("vibrance", -100.0, 100.0, 0.01, 100.0, &Parameters::vibrance);
    addScalar("fade", 0.0, 100.0, 0.01, 100.0, &Parameters::fade);

    static const char* const hslNames[]{"red",  "orange", "yellow", "green",
                                        "aqua", "blue",   "purple", "magenta"};
    for (int channel = 0; channel < HslChannelCount; ++channel) {
        const QString name = QString::fromLatin1(hslNames[channel]);
        add(QStringLiteral("hsl.%1.hue").arg(name), Field::HslHue, channel, 0, -100.0, 100.0, 0.01,
            100.0, nullptr);
        add(QStringLiteral("hsl.%1.saturation").arg(name), Field::HslSaturation, channel, 0, -100.0,
            100.0, 0.01, 100.0, nullptr);
        add(QStringLiteral("hsl.%1.luminance").arg(name), Field::HslLuminance, channel, 0, -100.0,
            100.0, 0.01, 100.0, nullptr);
    }

    static const char* const curveNames[]{"RGB", "R", "G", "B"};
    for (int channel = 0; channel < CurveChannelCount; ++channel) {
        for (int point = 0; point < CurvePointCount; ++point) {
            add(QStringLiteral("curve.%1.%2")
                    .arg(QString::fromLatin1(curveNames[channel]))
                    .arg(point),
                Field::CurvePoint, channel, point, 0.0, 100.0, 0.01, 100.0, nullptr);
        }
    }

    static const char* const gradeNames[]{"shadows", "midtones", "highlights"};
    for (int zone = 0; zone < GradeZoneCount; ++zone) {
        const QString name = QString::fromLatin1(gradeNames[zone]);
        add(QStringLiteral("grade.%1.hue").arg(name), Field::GradeHue, zone, 0, 0.0, 360.0, 1.0,
            1.0, nullptr);
        add(QStringLiteral("grade.%1.saturation").arg(name), Field::GradeSaturation, zone, 0, 0.0,
            100.0, 0.01, 100.0, nullptr);
        add(QStringLiteral("grade.%1.luminance").arg(name), Field::GradeLuminance, zone, 0, -100.0,
            100.0, 0.01, 100.0, nullptr);
    }
    addScalar("grade.blending", 0.0, 100.0, 0.01, 100.0, &Parameters::gradeBlending);
    addScalar("grade.balance", -100.0, 100.0, 0.01, 100.0, &Parameters::gradeBalance);

    // Detail and effects.
    addScalar("texture", 0.0, 100.0, 0.01, 100.0, &Parameters::texture);
    addScalar("clarity", 0.0, 100.0, 0.01, 100.0, &Parameters::clarity);
    addScalar("dehaze", 0.0, 100.0, 0.01, 100.0, &Parameters::dehaze);
    addScalar("sharpen", 0.0, 100.0, 0.01, 100.0, &Parameters::sharpen);
    addScalar("noise", 0.0, 100.0, 0.01, 100.0, &Parameters::noise);
    addScalar("colorNoise", 0.0, 100.0, 0.01, 100.0, &Parameters::colorNoise);
    addScalar("vignette", -100.0, 100.0, 0.01, 100.0, &Parameters::vignette);
    addScalar("feather", 0.0, 100.0, 0.01, 100.0, &Parameters::feather);
    addScalar("grain", 0.0, 100.0, 0.01, 100.0, &Parameters::grain);

    return registry;
}

const Registry& registry()
{
    static const Registry instance = buildRegistry();
    return instance;
}

double storedValue(const Parameters& parameters, const KeyInfo& info)
{
    switch (info.field) {
    case Field::Scalar:
        return parameters.*(info.member);
    case Field::HslHue:
        return parameters.hsl[info.index].hue;
    case Field::HslSaturation:
        return parameters.hsl[info.index].saturation;
    case Field::HslLuminance:
        return parameters.hsl[info.index].luminance;
    case Field::CurvePoint:
        return parameters.curves[info.index].points[info.sub];
    case Field::GradeHue:
        return parameters.grade[info.index].hue;
    case Field::GradeSaturation:
        return parameters.grade[info.index].saturation;
    case Field::GradeLuminance:
        return parameters.grade[info.index].luminance;
    }
    return 0.0;
}

void assignStoredValue(Parameters& parameters, const KeyInfo& info, double value)
{
    switch (info.field) {
    case Field::Scalar:
        parameters.*(info.member) = value;
        return;
    case Field::HslHue:
        parameters.hsl[info.index].hue = value;
        return;
    case Field::HslSaturation:
        parameters.hsl[info.index].saturation = value;
        return;
    case Field::HslLuminance:
        parameters.hsl[info.index].luminance = value;
        return;
    case Field::CurvePoint:
        parameters.curves[info.index].points[info.sub] = value;
        return;
    case Field::GradeHue:
        parameters.grade[info.index].hue = value;
        return;
    case Field::GradeSaturation:
        parameters.grade[info.index].saturation = value;
        return;
    case Field::GradeLuminance:
        parameters.grade[info.index].luminance = value;
        return;
    }
}

} // namespace

// ---------------------------------------------------------------------------
// Public key/value API
// ---------------------------------------------------------------------------

bool isParameterKey(const QString& key) { return registry().lookup.contains(key); }

QStringList parameterKeys() { return registry().keys; }

bool setParameter(Parameters& parameters, const QString& key, double uiValue)
{
    const Registry& table = registry();
    const auto iterator = table.lookup.constFind(key);
    if (iterator == table.lookup.constEnd())
        return false;
    const KeyInfo& info = table.infos[static_cast<std::size_t>(*iterator)];
    const double clampedUi =
        std::isfinite(uiValue) ? std::clamp(uiValue, info.uiMin, info.uiMax) : 0.0;
    assignStoredValue(parameters, info, clampedUi * info.storedPerUi);
    return true;
}

double parameterValue(const Parameters& parameters, const QString& key)
{
    const Registry& table = registry();
    const auto iterator = table.lookup.constFind(key);
    if (iterator == table.lookup.constEnd())
        return std::numeric_limits<double>::quiet_NaN();
    const KeyInfo& info = table.infos[static_cast<std::size_t>(*iterator)];
    return storedValue(parameters, info) * info.uiPerStored;
}

QVariantMap toUiValues(const Parameters& parameters)
{
    const Registry& table = registry();
    QVariantMap values;
    for (std::size_t i = 0; i < table.infos.size(); ++i) {
        values.insert(table.keys[static_cast<qsizetype>(i)],
                      storedValue(parameters, table.infos[i]) * table.infos[i].uiPerStored);
    }
    return values;
}

bool isGpuPreviewKey(const QString& key)
{
    return key == QStringLiteral("exposure") || key == QStringLiteral("brightness") ||
           key == QStringLiteral("contrast") || key == QStringLiteral("saturation") ||
           key == QStringLiteral("highlights") || key == QStringLiteral("shadows") ||
           key == QStringLiteral("whites") || key == QStringLiteral("blacks") ||
           key == QStringLiteral("temperature") || key == QStringLiteral("tint") ||
           key == QStringLiteral("vibrance");
}

bool isGpuPreviewSupported(const Parameters& input)
{
    const Parameters p = sanitized(input);

    // Stages the shader does not implement. Neutral values are allowed so a
    // user can drag a supported key after a curve was reset to linear, etc.
    if (p.fade != 0.0)
        return false;
    for (const auto& channel : p.hsl) {
        if (channel.hue != 0.0 || channel.saturation != 0.0 || channel.luminance != 0.0)
            return false;
    }
    for (const auto& curve : p.curves) {
        if (!isLinearCurve(curve))
            return false;
    }
    for (const auto& zone : p.grade) {
        // Hue alone cannot change pixels; blending/balance only shape an
        // already-active zone.
        if (zone.saturation != 0.0 || zone.luminance != 0.0)
            return false;
    }
    if (p.texture != 0.0 || p.clarity != 0.0 || p.dehaze != 0.0 || p.sharpen != 0.0 ||
        p.noise != 0.0 || p.colorNoise != 0.0 || p.vignette != 0.0 || p.grain != 0.0)
        return false;

    if (p.filterIntensity > 0.0 && isActivePreset(parsePreset(p.filterPreset)))
        return false;
    return true;
}

} // namespace NekoPic::Adjustments
