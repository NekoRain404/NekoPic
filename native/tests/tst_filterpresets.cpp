#include "core/filterpresets.h"

#include <QtTest>

using namespace NekoPic::Filters;

class FilterPresetsTest final : public QObject {
    Q_OBJECT
private slots:
    void exposesTwelveLooksPlusOriginal()
    {
        QCOMPARE(presetIds().size(), 13);
        QCOMPARE(presetIds().first(), QStringLiteral("none"));
        QVERIFY(isValidPreset(QStringLiteral("silver")));
        QVERIFY(!isValidPreset(QStringLiteral("neko")));
    }

    void metadataIsStable()
    {
        QCOMPARE(preset(QStringLiteral("vivid")).category, QStringLiteral("natural"));
        QCOMPARE(preset(QStringLiteral("film")).category, QStringLiteral("film"));
        QCOMPARE(preset(QStringLiteral("mono")).category, QStringLiteral("mono"));
        QCOMPARE(preset(QStringLiteral("unknown")).id, QStringLiteral("none"));
        QCOMPARE(defaultPreset(), QStringLiteral("none"));
    }

    void categoriesHaveNoDuplicates()
    {
        const auto categories = presetCategories();
        QCOMPARE(categories.toSet().size(), categories.size());
        QVERIFY(categories.contains(QStringLiteral("all")));
    }
};

QTEST_MAIN(FilterPresetsTest)
#include "tst_filterpresets.moc"
