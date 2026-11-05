#include "document/object.h"
#include "document/objectlayer.h"
#include "document/shapeobject.h"
#include "document/strokeobject.h"
#include "document/textobject.h"

#include <QColor>
#include <QColorSpace>
#include <QImage>
#include <QPainter>
#include <QtTest>

#include <cmath>
#include <limits>

using NekoPic::Document::DocumentObject;
using NekoPic::Document::InvalidObjectId;
using NekoPic::Document::ObjectId;
using NekoPic::Document::ObjectKind;
using NekoPic::Document::ObjectLayer;
using NekoPic::Document::ShapeKind;
using NekoPic::Document::ShapeObject;
using NekoPic::Document::StrokeObject;
using NekoPic::Document::TextObject;

namespace ShapeGeometry = NekoPic::Document::ShapeGeometry;

namespace {

QImage transparentImage(int width, int height,
                        QImage::Format format = QImage::Format_ARGB32_Premultiplied)
{
    QImage image(width, height, format);
    image.fill(Qt::transparent);
    return image;
}

QImage renderObject(const DocumentObject &object, int width = 300, int height = 200,
                    QPointF offset = {})
{
    QImage image = transparentImage(width, height);
    QPainter painter(&image);
    painter.setRenderHint(QPainter::Antialiasing, true);
    if (!offset.isNull())
        painter.translate(offset);
    object.render(painter);
    painter.end();
    return image;
}

QImage renderLayer(const ObjectLayer &layer, int width, int height,
                   QImage::Format format = QImage::Format_ARGB32_Premultiplied)
{
    QImage image = transparentImage(width, height, format);
    layer.renderOnto(image);
    return image;
}

int inkPixels(const QImage &image, int minimumAlpha = 0)
{
    int count = 0;
    for (int y = 0; y < image.height(); ++y) {
        for (int x = 0; x < image.width(); ++x) {
            if (qAlpha(image.pixel(x, y)) > minimumAlpha)
                ++count;
        }
    }
    return count;
}

bool colorNear(QRgb color, int red, int green, int blue, int alpha,
               int tolerance = 3)
{
    return std::abs(qRed(color) - red) <= tolerance
        && std::abs(qGreen(color) - green) <= tolerance
        && std::abs(qBlue(color) - blue) <= tolerance
        && std::abs(qAlpha(color) - alpha) <= tolerance;
}

QString rectDiff(const QRectF &actual, const QRectF &expected, qreal tolerance = 0.5)
{
    if (std::abs(actual.x() - expected.x()) <= tolerance
        && std::abs(actual.y() - expected.y()) <= tolerance
        && std::abs(actual.width() - expected.width()) <= tolerance
        && std::abs(actual.height() - expected.height()) <= tolerance) {
        return {};
    }
    return QStringLiteral("actual (%1, %2, %3, %4), expected (%5, %6, %7, %8)")
        .arg(actual.x()).arg(actual.y()).arg(actual.width()).arg(actual.height())
        .arg(expected.x()).arg(expected.y()).arg(expected.width()).arg(expected.height());
}

} // namespace

class ObjectsTest final : public QObject {
    Q_OBJECT

private slots:
    void idsAreMonotonicAndClonesGetFreshIds();
    void textRendersInkWithinBounds();
    void chineseTextRenders();
    void textHitTesting();
    void shapeRectAndEllipseRender();
    void shapeLineAndPolygonRender();
    void arrowHeadRenders();
    void shiftConstraints();
    void strokeRoundCapsAndBounds();
    void strokeSampleLimit();
    void strokeSoftnessClampsAndFeathers();
    void layerZOrderAndTopmostHit();
    void layerVisibilityAndLockFiltering();
    void layerReordering();
    void layerRenderPreservesTargetProperties();
    void layerOpacityBlends();
    void layerApplyTransformMovesBounds();
    void layerCropTranslatesAndClips();
    void cloneIsIndependent();
};

void ObjectsTest::idsAreMonotonicAndClonesGetFreshIds()
{
    StrokeObject first;
    StrokeObject second;
    QVERIFY(first.id() != InvalidObjectId);
    QVERIFY(second.id() > first.id());

    const auto clone = first.clone();
    QVERIFY(clone);
    QVERIFY(clone->id() != first.id());
    QVERIFY(clone->id() > second.id());

    first.setOpacity(4.0);
    QVERIFY(qFuzzyCompare(first.opacity(), 1.0));
    first.setOpacity(-1.0);
    QCOMPARE(first.opacity(), 0.0);
}

void ObjectsTest::textRendersInkWithinBounds()
{
    TextObject text(QStringLiteral("Hello object model"));
    text.setFontFamily(QStringLiteral("DejaVu Sans"));
    text.setFontPointSize(24.0);
    text.setColor(Qt::black);

    const QRectF bounds = text.bounds();
    QVERIFY(bounds.width() > 20.0);
    QVERIFY(bounds.height() > 10.0);

    const QImage image = renderObject(text, 400, 200);
    QVERIFY(inkPixels(image) > 100);

    // Every rasterised pixel must fall inside the reported bounds. One pixel
    // of slack covers antialiasing coverage at the path edge.
    const QRectF tolerant = bounds.adjusted(-1.0, -1.0, 1.0, 1.0);
    for (int y = 0; y < image.height(); ++y) {
        for (int x = 0; x < image.width(); ++x) {
            if (qAlpha(image.pixel(x, y)) == 0)
                continue;
            QVERIFY2(tolerant.contains(QPointF(x + 0.5, y + 0.5)),
                     qPrintable(QStringLiteral("ink pixel (%1, %2) outside bounds (%3, %4, %5, %6)")
                         .arg(x).arg(y)
                         .arg(bounds.x()).arg(bounds.y())
                         .arg(bounds.width()).arg(bounds.height())));
        }
    }
}

void ObjectsTest::chineseTextRenders()
{
    // Linux font fallback must resolve CJK glyphs; there is no bundled font.
    TextObject text(QString::fromUtf8("你好世界"));
    text.setFontFamily(QStringLiteral("Noto Sans"));
    text.setFontPointSize(28.0);
    text.setColor(Qt::black);

    const QImage image = renderObject(text, 400, 160);
    QVERIFY2(inkPixels(image) > 100,
             "Chinese text produced no visible glyph ink (font fallback failed)");

    const QRectF bounds = text.bounds();
    QVERIFY(bounds.width() > 20.0);
    QVERIFY(bounds.height() > 10.0);
}

void ObjectsTest::textHitTesting()
{
    TextObject text(QStringLiteral("Hit me"));
    text.setFontPointSize(24.0);
    text.setColor(Qt::black);

    const QRectF bounds = text.bounds();
    QVERIFY(text.hitTest(bounds.center(), 0.0));
    QVERIFY(!text.hitTest(bounds.bottomRight() + QPointF(30.0, 30.0), 0.0));

    // Tolerance widens the line box into the padding area.
    QVERIFY(!text.hitTest(bounds.topLeft() + QPointF(2.0, 2.0), 0.0));
    QVERIFY(text.hitTest(bounds.topLeft() + QPointF(2.0, 2.0), 4.0));

    text.setLocked(true);
    QVERIFY(!text.hitTest(bounds.center(), 0.0));
}

void ObjectsTest::shapeRectAndEllipseRender()
{
    ShapeObject rectangle(ShapeKind::Rectangle);
    rectangle.setRect(QRectF(10.0, 10.0, 40.0, 30.0));
    rectangle.setFillColor(Qt::red);
    rectangle.setStrokeWidth(0.0);

    const QImage rectImage = renderObject(rectangle, 80, 60);
    QVERIFY(colorNear(rectImage.pixel(30, 25), 255, 0, 0, 255));
    QCOMPARE(qAlpha(rectImage.pixel(2, 2)), 0);
    QVERIFY2(rectDiff(rectangle.bounds(), QRectF(10.0, 10.0, 40.0, 30.0)).isEmpty(),
             qPrintable(rectDiff(rectangle.bounds(), QRectF(10.0, 10.0, 40.0, 30.0))));

    ShapeObject ellipse(ShapeKind::Ellipse);
    ellipse.setRect(QRectF(10.0, 10.0, 40.0, 30.0));
    ellipse.setFillColor(Qt::red);
    ellipse.setStrokeWidth(0.0);

    const QImage ellipseImage = renderObject(ellipse, 80, 60);
    QVERIFY(colorNear(ellipseImage.pixel(30, 25), 255, 0, 0, 255));
    QCOMPARE(qAlpha(ellipseImage.pixel(11, 11)), 0);
}

void ObjectsTest::shapeLineAndPolygonRender()
{
    ShapeObject line(ShapeKind::Line);
    line.setPoints({{10.0, 50.0}, {90.0, 50.0}});
    line.setStrokeColor(Qt::blue);
    line.setStrokeWidth(6.0);

    const QImage lineImage = renderObject(line, 120, 100);
    QVERIFY(colorNear(lineImage.pixel(50, 50), 0, 0, 255, 255, 8));
    QCOMPARE(qAlpha(lineImage.pixel(50, 70)), 0);

    ShapeObject polygon(ShapeKind::Polygon);
    polygon.setPoints({{10.0, 80.0}, {50.0, 20.0}, {90.0, 80.0}});
    polygon.setFillColor(Qt::green);
    polygon.setStrokeWidth(0.0);

    const QImage polygonImage = renderObject(polygon, 120, 100);
    QVERIFY(colorNear(polygonImage.pixel(50, 60), 0, 255, 0, 255));
    QCOMPARE(qAlpha(polygonImage.pixel(15, 25)), 0);
}

void ObjectsTest::arrowHeadRenders()
{
    ShapeObject arrow(ShapeKind::Arrow);
    arrow.setPoints({{20.0, 50.0}, {120.0, 50.0}});
    arrow.setStrokeColor(Qt::black);
    arrow.setStrokeWidth(4.0);

    const QImage image = renderObject(arrow, 160, 100);
    QVERIFY(qAlpha(image.pixel(50, 50)) > 0);   // shaft
    QVERIFY(qAlpha(image.pixel(100, 56)) > 0);  // head wing, outside shaft width
    QCOMPARE(qAlpha(image.pixel(100, 70)), 0);

    const QRectF bounds = arrow.bounds();
    QVERIFY(bounds.width() >= 100.0);
    QVERIFY(bounds.height() > arrow.strokeWidth() * 2.0);
}

void ObjectsTest::shiftConstraints()
{
    const QRectF square = ShapeGeometry::squareFromDrag(QPointF(10.0, 10.0),
                                                        QPointF(60.0, 30.0));
    QVERIFY2(rectDiff(square, QRectF(10.0, 10.0, 50.0, 50.0), 1e-9).isEmpty(),
             qPrintable(rectDiff(square, QRectF(10.0, 10.0, 50.0, 50.0), 1e-9)));

    const QRectF reverse = ShapeGeometry::squareFromDrag(QPointF(60.0, 60.0),
                                                         QPointF(10.0, 30.0));
    QVERIFY2(rectDiff(reverse, QRectF(10.0, 10.0, 50.0, 50.0), 1e-9).isEmpty(),
             qPrintable(rectDiff(reverse, QRectF(10.0, 10.0, 50.0, 50.0), 1e-9)));

    const qreal length = std::hypot(10.0, 7.0);
    const QPointF diagonal = ShapeGeometry::snapToAngle(QPointF(0.0, 0.0),
                                                        QPointF(10.0, 7.0));
    QVERIFY(std::abs(diagonal.x() - diagonal.y()) < 1e-9);
    QVERIFY(std::abs(std::hypot(diagonal.x(), diagonal.y()) - length) < 1e-9);

    const QPointF horizontal = ShapeGeometry::snapToAngle(QPointF(0.0, 0.0),
                                                          QPointF(10.0, 1.0), 90.0);
    QVERIFY(std::abs(horizontal.y()) < 1e-9);
    QVERIFY(std::abs(horizontal.x() - std::hypot(10.0, 1.0)) < 1e-9);
}

void ObjectsTest::strokeRoundCapsAndBounds()
{
    StrokeObject stroke;
    stroke.setPoints({{10.0, 50.0}, {50.0, 50.0}});
    stroke.setDiameter(10.0);
    stroke.setColor(Qt::black);

    const QRectF expected(5.0, 45.0, 50.0, 10.0);
    QVERIFY2(rectDiff(stroke.bounds(), expected, 0.75).isEmpty(),
             qPrintable(rectDiff(stroke.bounds(), expected, 0.75)));

    const QImage image = renderObject(stroke, 80, 80);
    // A round cap reaches 5 px past the endpoint; (7, 50) is inside the cap,
    // (4, 50) is outside it. A butt cap would leave (7, 50) blank.
    QVERIFY(qAlpha(image.pixel(7, 50)) > 0);
    QCOMPARE(qAlpha(image.pixel(4, 50)), 0);
    QVERIFY(qAlpha(image.pixel(50, 50)) > 0);
}

void ObjectsTest::strokeSampleLimit()
{
    StrokeObject stroke;
    for (qsizetype i = 0; i < StrokeObject::MaxSamples; ++i)
        QVERIFY(stroke.addPoint(QPointF(i % 100, i / 100)));

    QCOMPARE(stroke.sampleCount(), StrokeObject::MaxSamples);
    QVERIFY(!stroke.addPoint(QPointF(0.0, 0.0)));
    QCOMPARE(stroke.sampleCount(), StrokeObject::MaxSamples);

    QVector<QPointF> tooMany;
    tooMany.resize(StrokeObject::MaxSamples + 100);
    stroke.setPoints(tooMany);
    QCOMPARE(stroke.sampleCount(), StrokeObject::MaxSamples);
}

void ObjectsTest::strokeSoftnessClampsAndFeathers()
{
    StrokeObject hard;
    hard.setPoints({{20.0, 60.0}, {80.0, 60.0}});
    hard.setDiameter(16.0);
    hard.setColor(Qt::black);
    QCOMPARE(hard.softness(), 0.0);

    hard.setSoftness(-0.5);
    QCOMPARE(hard.softness(), 0.0);
    hard.setSoftness(2.0);
    QCOMPARE(hard.softness(), 1.0);
    hard.setSoftness(std::numeric_limits<qreal>::quiet_NaN());
    QCOMPARE(hard.softness(), 0.0);

    StrokeObject feather = hard;
    feather.setSoftness(1.0);
    QCOMPARE(feather.softness(), 1.0);
    QVERIFY2(rectDiff(feather.bounds(), hard.bounds(), 0.75).isEmpty(),
             "softening must not grow the hard-brush bounds");

    const QImage hardImage = renderObject(hard, 110, 120);
    const QImage softImage = renderObject(feather, 110, 120);
    const int hardCentre = qAlpha(hardImage.pixel(50, 60));
    const int softCentre = qAlpha(softImage.pixel(50, 60));
    const int softRim = qAlpha(softImage.pixel(50, 53));
    QVERIFY(hardCentre > 200);
    QVERIFY(softCentre > 200);
    QVERIFY2(softRim > 0, "the feathered stroke must still reach its soft rim");
    QVERIFY2(softRim < softCentre, "the soft rim must fade towards the edge");

    // Single points use the radial-gradient path.
    StrokeObject dot;
    dot.setPoints({{50.0, 60.0}});
    dot.setDiameter(40.0);
    dot.setColor(Qt::black);
    dot.setSoftness(1.0);
    const QImage dotImage = renderObject(dot, 110, 120);
    const int dotCentre = qAlpha(dotImage.pixel(50, 60));
    const int dotMid = qAlpha(dotImage.pixel(62, 60));
    QVERIFY(dotCentre > 200);
    QVERIFY(dotMid > 0);
    QVERIFY(dotMid < dotCentre);
}

void ObjectsTest::layerZOrderAndTopmostHit()
{
    ObjectLayer layer;

    ShapeObject red(ShapeKind::Rectangle);
    red.setRect(QRectF(0.0, 0.0, 80.0, 80.0));
    red.setFillColor(Qt::red);
    red.setStrokeWidth(0.0);

    ShapeObject blue(ShapeKind::Rectangle);
    blue.setRect(QRectF(40.0, 40.0, 80.0, 80.0));
    blue.setFillColor(Qt::blue);
    blue.setStrokeWidth(0.0);

    const ObjectId redId = layer.add(red.clone());
    const ObjectId blueId = layer.add(blue.clone());
    QCOMPARE(layer.size(), qsizetype(2));

    const QImage image = renderLayer(layer, 150, 150);
    QVERIFY(colorNear(image.pixel(60, 60), 0, 0, 255, 255));
    QVERIFY(colorNear(image.pixel(10, 10), 255, 0, 0, 255));

    QCOMPARE(layer.hitTest(QPointF(60.0, 60.0)), blueId);
    QCOMPARE(layer.hitTest(QPointF(10.0, 10.0)), redId);
    QCOMPARE(layer.hitTest(QPointF(140.0, 10.0)), InvalidObjectId);
}

void ObjectsTest::layerVisibilityAndLockFiltering()
{
    ObjectLayer layer;

    ShapeObject red(ShapeKind::Rectangle);
    red.setRect(QRectF(0.0, 0.0, 80.0, 80.0));
    red.setFillColor(Qt::red);
    red.setStrokeWidth(0.0);

    ShapeObject blue(ShapeKind::Rectangle);
    blue.setRect(QRectF(40.0, 40.0, 80.0, 80.0));
    blue.setFillColor(Qt::blue);
    blue.setStrokeWidth(0.0);

    const ObjectId redId = layer.add(red.clone());
    const ObjectId blueId = layer.add(blue.clone());

    layer.object(blueId)->setVisible(false);
    QCOMPARE(layer.hitTest(QPointF(60.0, 60.0)), redId);
    const QImage hidden = renderLayer(layer, 150, 150);
    QVERIFY(colorNear(hidden.pixel(60, 60), 255, 0, 0, 255));

    layer.object(blueId)->setVisible(true);
    layer.object(redId)->setLocked(true);
    QCOMPARE(layer.hitTest(QPointF(10.0, 10.0)), InvalidObjectId);
    QCOMPARE(layer.hitTest(QPointF(60.0, 60.0)), blueId);
}

void ObjectsTest::layerReordering()
{
    ObjectLayer layer;

    ShapeObject red(ShapeKind::Rectangle);
    red.setRect(QRectF(0.0, 0.0, 50.0, 50.0));
    red.setFillColor(Qt::red);
    red.setStrokeWidth(0.0);

    ShapeObject blue(ShapeKind::Rectangle);
    blue.setRect(QRectF(25.0, 25.0, 50.0, 50.0));
    blue.setFillColor(Qt::blue);
    blue.setStrokeWidth(0.0);

    const ObjectId redId = layer.add(red.clone());
    const ObjectId blueId = layer.add(blue.clone());

    QVERIFY(layer.ids() == QList<ObjectId>({redId, blueId}));
    QVERIFY(layer.lower(blueId));
    QVERIFY(layer.ids() == QList<ObjectId>({blueId, redId}));
    QVERIFY(layer.raise(blueId));
    QVERIFY(layer.ids() == QList<ObjectId>({redId, blueId}));
    QVERIFY(layer.sendToBack(blueId));
    QVERIFY(layer.ids() == QList<ObjectId>({blueId, redId}));
    QVERIFY(layer.bringToFront(blueId));
    QVERIFY(layer.ids() == QList<ObjectId>({redId, blueId}));
    QVERIFY(!layer.bringToFront(blueId));

    QVERIFY(layer.moveTo(blueId, 0));
    QVERIFY(layer.ids() == QList<ObjectId>({blueId, redId}));
    QVERIFY(!layer.moveTo(ObjectId(999999), 0));
}

void ObjectsTest::layerRenderPreservesTargetProperties()
{
    QImage target(120, 80, QImage::Format_RGBA8888);
    target.fill(Qt::transparent);
    const QColorSpace colorSpace(QColorSpace::AdobeRgb);
    target.setColorSpace(colorSpace);
    target.setDotsPerMeterX(11811);
    target.setDotsPerMeterY(11811);
    target.setPixel(119, 79, qRgba(1, 2, 3, 100));

    ShapeObject rectangle(ShapeKind::Rectangle);
    rectangle.setRect(QRectF(10.0, 10.0, 40.0, 30.0));
    rectangle.setFillColor(Qt::red);
    rectangle.setStrokeWidth(0.0);

    ObjectLayer layer;
    layer.add(rectangle.clone());
    layer.renderOnto(target);

    QCOMPARE(target.format(), QImage::Format_RGBA8888);
    QVERIFY(target.colorSpace() == colorSpace);
    QCOMPARE(target.dotsPerMeterX(), 11811);
    QCOMPARE(target.dotsPerMeterY(), 11811);
    QCOMPARE(qAlpha(target.pixel(0, 0)), 0);
    QVERIFY(qAlpha(target.pixel(20, 20)) > 0);
    QCOMPARE(target.pixel(119, 79), qRgba(1, 2, 3, 100));
}

void ObjectsTest::layerOpacityBlends()
{
    QImage target(60, 60, QImage::Format_RGBA8888);
    target.fill(QColor(0, 0, 0));

    ShapeObject rectangle(ShapeKind::Rectangle);
    rectangle.setRect(QRectF(0.0, 0.0, 60.0, 60.0));
    rectangle.setFillColor(Qt::red);
    rectangle.setStrokeWidth(0.0);
    rectangle.setOpacity(0.5);

    ObjectLayer layer;
    layer.add(rectangle.clone());
    layer.renderOnto(target);

    const QRgb blended = target.pixel(30, 30);
    QCOMPARE(qAlpha(blended), 255);
    QVERIFY2(std::abs(qRed(blended) - 128) <= 3,
             qPrintable(QStringLiteral("red channel was %1").arg(qRed(blended))));
    QVERIFY(qGreen(blended) <= 3);
    QVERIFY(qBlue(blended) <= 3);

    // Fully transparent object contributes nothing.
    ObjectLayer invisible;
    rectangle.setOpacity(0.0);
    invisible.add(rectangle.clone());
    const QImage empty = renderLayer(invisible, 60, 60);
    QCOMPARE(inkPixels(empty), 0);
}

void ObjectsTest::layerApplyTransformMovesBounds()
{
    ShapeObject rectangle(ShapeKind::Rectangle);
    rectangle.setRect(QRectF(10.0, 0.0, 20.0, 10.0));
    rectangle.setFillColor(Qt::red);
    rectangle.setStrokeWidth(0.0);

    ObjectLayer rotated;
    const ObjectId rotatedId = rotated.add(rectangle.clone());
    QTransform rotation;
    rotation.rotate(90.0);
    rotated.applyTransform(rotation);

    const QRectF expectedRotated(-10.0, 10.0, 10.0, 20.0);
    QVERIFY2(rectDiff(rotated.object(rotatedId)->bounds(), expectedRotated, 1e-6).isEmpty(),
             qPrintable(rectDiff(rotated.object(rotatedId)->bounds(), expectedRotated, 1e-6)));

    ObjectLayer flipped;
    const ObjectId flippedId = flipped.add(rectangle.clone());
    QTransform flip;
    flip.scale(-1.0, 1.0);
    flipped.applyTransform(flip);
    const QRectF expectedFlipped(-30.0, 0.0, 20.0, 10.0);
    QVERIFY2(rectDiff(flipped.object(flippedId)->bounds(), expectedFlipped, 1e-6).isEmpty(),
             qPrintable(rectDiff(flipped.object(flippedId)->bounds(), expectedFlipped, 1e-6)));

    // Rotation about the image centre also moves the rendered pixels.
    ObjectLayer visual;
    const ObjectId visualId = visual.add(rectangle.clone());
    QTransform aboutCentre;
    aboutCentre.translate(50.0, 50.0);
    aboutCentre.rotate(90.0);
    aboutCentre.translate(-50.0, -50.0);
    visual.applyTransform(aboutCentre);

    const QImage image = renderLayer(visual, 200, 100);
    QVERIFY(qAlpha(image.pixel(95, 20)) > 0);
    QCOMPARE(visual.hitTest(QPointF(95.0, 20.0)), visualId);
}

void ObjectsTest::layerCropTranslatesAndClips()
{
    ObjectLayer layer;

    ShapeObject inside(ShapeKind::Rectangle);
    inside.setRect(QRectF(20.0, 20.0, 30.0, 30.0));
    inside.setFillColor(Qt::red);
    inside.setStrokeWidth(0.0);

    ShapeObject partial(ShapeKind::Rectangle);
    partial.setRect(QRectF(90.0, 10.0, 30.0, 30.0));
    partial.setFillColor(Qt::blue);
    partial.setStrokeWidth(0.0);

    ShapeObject outside(ShapeKind::Rectangle);
    outside.setRect(QRectF(200.0, 200.0, 10.0, 10.0));
    outside.setFillColor(Qt::green);
    outside.setStrokeWidth(0.0);

    const ObjectId insideId = layer.add(inside.clone());
    const ObjectId partialId = layer.add(partial.clone());
    const ObjectId outsideId = layer.add(outside.clone());

    layer.crop(QRect(10, 10, 100, 100), QPoint(-10, -10));

    QCOMPARE(layer.size(), qsizetype(2));
    QVERIFY(layer.object(insideId) != nullptr);
    QVERIFY(layer.object(partialId) != nullptr);
    QVERIFY(layer.object(outsideId) == nullptr);

    QVERIFY2(rectDiff(layer.object(insideId)->bounds(),
                      QRectF(10.0, 10.0, 30.0, 30.0), 1e-6).isEmpty(),
             qPrintable(rectDiff(layer.object(insideId)->bounds(),
                                 QRectF(10.0, 10.0, 30.0, 30.0), 1e-6)));
    QVERIFY2(rectDiff(layer.object(partialId)->bounds(),
                      QRectF(80.0, 0.0, 30.0, 30.0), 1e-6).isEmpty(),
             qPrintable(rectDiff(layer.object(partialId)->bounds(),
                                 QRectF(80.0, 0.0, 30.0, 30.0), 1e-6)));

    // Rendering into the cropped-size target clips the surviving partial
    // object without baking or altering its geometry.
    const QImage cropped = renderLayer(layer, 100, 100);
    QVERIFY(qAlpha(cropped.pixel(90, 5)) > 0);
    QCOMPARE(qAlpha(cropped.pixel(95, 90)), 0);

    // Convenience overload: new origin is kept.topLeft().
    layer.crop(QRect(0, 0, 50, 50));
    QCOMPARE(layer.size(), qsizetype(1));
    QVERIFY(layer.object(insideId) != nullptr);
}

void ObjectsTest::cloneIsIndependent()
{
    TextObject original(QStringLiteral("A"));
    original.setColor(Qt::red);
    original.setOpacity(0.5);
    original.setPadding(2.0);

    const auto clone = original.clone();
    QVERIFY(clone);
    QVERIFY(clone->id() != original.id());
    QVERIFY(clone->kind() == ObjectKind::Text);

    auto *textClone = dynamic_cast<TextObject *>(clone.get());
    QVERIFY(textClone);
    QVERIFY(textClone->text() == QStringLiteral("A"));

    textClone->setText(QStringLiteral("B"));
    textClone->setColor(Qt::blue);
    textClone->setOpacity(0.2);
    QVERIFY(original.text() == QStringLiteral("A"));
    QVERIFY(original.color() == QColor(Qt::red));
    QVERIFY(qFuzzyCompare(original.opacity(), 0.5));

    clone->applyTransform(QTransform::fromTranslate(100.0, 0.0));
    QVERIFY(original.translation() == QPointF(0.0, 0.0));
    QVERIFY(clone->translation() == QPointF(100.0, 0.0));

    ShapeObject polygon(ShapeKind::Polygon);
    polygon.setPoints({{0.0, 0.0}, {10.0, 0.0}, {10.0, 10.0}});
    const auto polygonClone = polygon.clone();
    auto *polygonCopy = dynamic_cast<ShapeObject *>(polygonClone.get());
    QVERIFY(polygonCopy);
    polygonCopy->setPoints({{0.0, 0.0}, {5.0, 5.0}});
    QCOMPARE(polygon.points().size(), qsizetype(3));
    QCOMPARE(polygonCopy->points().size(), qsizetype(2));
}

QTEST_MAIN(ObjectsTest)
#include "tst_objects.moc"
