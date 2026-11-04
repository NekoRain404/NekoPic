#include "imageio.h"

#include <QColorSpace>
#include <QFileInfo>
#include <QImageReader>
#include <QImageWriter>
#include <QPainter>
#include <QSaveFile>

#include <utility>

namespace NekoPic::ImageIO {
namespace {
bool withinLimits(const QSize &size, const Limits &limits)
{
    return limits.maxDimension > 0 && limits.maxPixels > 0
        && size.width() > 0 && size.height() > 0
        && size.width() <= limits.maxDimension && size.height() <= limits.maxDimension
        && qint64(size.width()) * size.height() <= limits.maxPixels;
}
}

QList<QByteArray> supportedReadFormats()
{
    return QImageReader::supportedImageFormats();
}

LoadResult load(const QString &path, const Limits &limits)
{
    QImageReader reader(path);
    reader.setAutoTransform(true);
    if (!reader.canRead())
        return {{}, reader.errorString()};
    // Unknown dimensions cannot be safely checked before allocating the image.
    if (!withinLimits(reader.size(), limits))
        return {{}, QStringLiteral("Image dimensions are unavailable or exceed the limit")};
    QImage image = reader.read();
    if (image.isNull())
        return {{}, reader.errorString()};
    if (!withinLimits(image.size(), limits))
        return {{}, QStringLiteral("Decoded image exceeds the dimension limit")};
    return {std::move(image), {}};
}

SaveResult save(const QString &path, const QImage &image, const SaveOptions &options)
{
    if (image.isNull())
        return {false, QStringLiteral("Cannot save an empty image")};
    QByteArray format = options.format.toLower();
    if (format.isEmpty())
        format = QFileInfo(path).suffix().toLatin1().toLower();
    if (format == "jpg")
        format = "jpeg";
    if (format != "png" && format != "jpeg")
        return {false, QStringLiteral("Only PNG and JPEG output are supported")};
    if (options.quality < -1 || options.quality > 100)
        return {false, QStringLiteral("Quality must be between 0 and 100, or -1")};

    QImage output = image;
    if (format == "jpeg" && image.hasAlphaChannel()) {
        if (!options.jpegBackground.isValid() || options.jpegBackground.alpha() != 255)
            return {false, QStringLiteral("JPEG background must be an opaque color")};
        output = QImage(image.size(), image.depth() > 32 ? QImage::Format_RGBX64 : QImage::Format_RGB32);
        if (output.isNull())
            return {false, QStringLiteral("Could not allocate JPEG image")};
        output.setColorSpace(image.colorSpace());
        output.setDotsPerMeterX(image.dotsPerMeterX());
        output.setDotsPerMeterY(image.dotsPerMeterY());
        output.fill(options.jpegBackground);
        QPainter painter(&output);
        painter.drawImage(0, 0, image);
    }

    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly))
        return {false, file.errorString()};
    QImageWriter writer(&file, format);
    writer.setQuality(options.quality);
    if (!writer.write(output))
        return {false, writer.errorString()};
    if (!file.commit())
        return {false, file.errorString()};
    return {true, {}};
}
} // namespace NekoPic::ImageIO
