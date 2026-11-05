// NekoPic pipeline benchmark harness.
//
// This is a measurement tool, not a correctness test. It runs against the real
// production code (core/adjustments, core/mosaic, io/imageio,
// render/previewmath, document/history) with deterministic synthetic images.
//
// Usage:
//   bench_pipeline [--quick] [--runs N] [--jobs N] [--csv PATH] [--json PATH] [--check]
//
// Default output is Markdown on stdout. --quick uses smaller dimensions so the
// harness can be smoke-run during development. Independent adjustment cases
// run concurrently through the Qt thread pool (up to 8 by default) so the full
// 48 MP matrix stays inside a ~2 minute budget; each individual case is still a
// single-threaded loop. Use --jobs 1 for isolated, serial timings. --check
// compares a small set of advisory regression ceilings and exits non-zero on
// violation.
//
// The harness is intentionally not registered with CTest: it is a slow,
// machine-specific measurement. If a deployment wants a smoke gate, register
// only the quick mode explicitly:
//   add_test(NAME bench_pipeline_smoke COMMAND bench_pipeline --quick)
// and give it a generous timeout.

#include "core/adjustments.h"
#include "core/filterpresets.h"
#include "core/mosaic.h"
#include "document/history.h"
#include "io/imageio.h"
#include "render/previewmath.h"

#include <QCoreApplication>
#include <QDir>
#include <QElapsedTimer>
#include <QEventLoop>
#include <QFile>
#include <QFileInfo>
#include <QFutureWatcher>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSysInfo>
#include <QTextStream>
#include <QThread>
#include <QThreadPool>
#include <QtConcurrentRun>

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstdio>
#include <functional>
#include <vector>

#ifndef NEKOPIC_BENCH_SOURCE_DIR
#define NEKOPIC_BENCH_SOURCE_DIR "."
#endif

namespace {

constexpr qint64 kiB = 1024;
constexpr qint64 miB = 1024 * kiB;
constexpr qint64 giB = 1024 * miB;
constexpr qint64 hardMemoryCap = 1 * giB;

// Consume results so the optimizer cannot discard the work under test.
std::atomic<quint64> g_sink{0};

struct Options
{
    bool quick = false;
    bool check = false;
    int runs = 5;
    // 0 selects a conservative automatic value. Independent adjustment cases
    // are evaluated concurrently to keep the full matrix inside the runtime
    // budget; each individual case still runs single-threaded.
    int jobs = 0;
    QString csvPath;
    QString jsonPath;
};

struct SizeSpec
{
    QString label;
    int width = 0;
    int height = 0;
};

struct Stats
{
    int runs = 0;
    double min = 0.0;
    double median = 0.0;
    double p95 = 0.0;
    double max = 0.0;
};

struct Row
{
    QString suite;
    QString caseName;
    QString format;
    QString sizeLabel;
    QString note;
    int width = 0;
    int height = 0;
    int runs = 0;
    double minMs = 0.0;
    double medianMs = 0.0;
    double p95Ms = 0.0;
    double maxMs = 0.0;
    qint64 sourceBytes = 0;
    qint64 resultBytes = 0;
    qint64 undoEntries = -1;
    qint64 accountedPeakBytes = -1;
    bool skipped = false;
};

QString formatMs(double value)
{
    if (value < 0.0)
        return QStringLiteral("-");
    if (value < 10.0)
        return QString::number(value, 'f', 3);
    if (value < 100.0)
        return QString::number(value, 'f', 2);
    return QString::number(value, 'f', 1);
}

QString formatMb(qint64 bytes)
{
    if (bytes < 0)
        return QStringLiteral("-");
    return QString::number(double(bytes) / double(miB), 'f', 1);
}

QString readProcValue(const QString& path, const QString& prefix)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return {};
    // /proc entries report a stat size of zero, so QFile::atEnd() is not
    // reliable here; read the whole pseudo-file and split it ourselves.
    const auto contents = QString::fromUtf8(file.readAll());
    const auto lines = contents.split(QLatin1Char('\n'));
    for (const auto& rawLine : lines) {
        const auto line = rawLine.trimmed();
        if (line.startsWith(prefix)) {
            auto value = line.mid(prefix.size()).trimmed();
            if (value.startsWith(QLatin1Char(':')))
                value = value.mid(1).trimmed();
            return value;
        }
    }
    return {};
}

QString compilerName()
{
#if defined(__clang__)
    return QStringLiteral("Clang %1.%2.%3")
        .arg(__clang_major__)
        .arg(__clang_minor__)
        .arg(__clang_patchlevel__);
#elif defined(__GNUC__)
    return QStringLiteral("GCC %1.%2.%3")
        .arg(__GNUC__)
        .arg(__GNUC_MINOR__)
        .arg(__GNUC_PATCHLEVEL__);
#elif defined(_MSC_VER)
    return QStringLiteral("MSVC %1").arg(_MSC_VER);
#else
    return QStringLiteral("unknown compiler");
#endif
}

QByteArray buildName()
{
#if defined(NDEBUG)
    return QByteArrayLiteral("Release (NDEBUG)");
#else
    return QByteArrayLiteral("Debug (no NDEBUG)");
#endif
}

struct Environment
{
    QString cpu;
    QString memory;
    QString os;
    QString qtRuntime;
    QString qtBuilt;
    QString compiler;
    QString build;
    QString load;
    int logicalCores = 0;

    QString markdown() const
    {
        QString text;
        text += QStringLiteral("- **CPU**: %1 (%2 logical cores)\n").arg(cpu).arg(logicalCores);
        text += QStringLiteral("- **RAM**: %1\n").arg(memory);
        text += QStringLiteral("- **OS**: %1\n").arg(os);
        text += QStringLiteral("- **Qt**: runtime %1, built against %2\n").arg(qtRuntime, qtBuilt);
        text += QStringLiteral("- **Compiler**: %1\n").arg(compiler);
        text += QStringLiteral("- **Build**: %1\n").arg(build);
        text += QStringLiteral("- **Load average at start**: %1\n").arg(load);
        return text;
    }
};

Environment gatherEnvironment()
{
    Environment env;
    env.cpu = readProcValue(QStringLiteral("/proc/cpuinfo"), QStringLiteral("model name"));
    if (env.cpu.isEmpty())
        env.cpu = QSysInfo::currentCpuArchitecture();
    const auto memTotal =
        readProcValue(QStringLiteral("/proc/meminfo"), QStringLiteral("MemTotal:"));
    env.memory = memTotal.isEmpty() ? QStringLiteral("unknown") : memTotal;
    env.os = QSysInfo::prettyProductName();
    env.qtRuntime = QString::fromLatin1(qVersion());
    env.qtBuilt = QStringLiteral(QT_VERSION_STR);
    env.compiler = compilerName();
    env.build = QString::fromLatin1(buildName());
    env.logicalCores = QThread::idealThreadCount();
    QFile loadFile(QStringLiteral("/proc/loadavg"));
    if (loadFile.open(QIODevice::ReadOnly | QIODevice::Text))
        env.load = QString::fromUtf8(loadFile.readLine()).trimmed();
    else
        env.load = QStringLiteral("unknown");
    return env;
}

QImage makeSyntheticImage(int width, int height, QImage::Format format, quint32 seed)
{
    if (width <= 0 || height <= 0)
        return {};
    QImage image(width, height, format);
    if (image.isNull())
        return {};

    if (format == QImage::Format_RGBA64) {
        for (int y = 0; y < height; ++y) {
            auto* line = reinterpret_cast<QRgba64*>(image.scanLine(y));
            quint32 state = seed ^ quint32(y * 2654435761u);
            const quint32 greenBase =
                quint32((quint64(y) * 65535u) / quint64(std::max(1, height - 1)));
            for (int x = 0; x < width; ++x) {
                state = state * 1664525u + 1013904223u;
                const quint16 noise = quint16(state >> 16);
                const quint16 red =
                    quint16((quint32((quint64(x) * 65535u) / quint64(std::max(1, width - 1))) +
                             (noise & 0x1ffu)) &
                            0xffffu);
                const quint16 green = quint16((greenBase + ((noise >> 2) & 0x1ffu)) & 0xffffu);
                const quint16 blue = quint16((noise * 3u + quint32(x * 7)) & 0xffffu);
                line[x] = QRgba64::fromRgba64(red, green, blue, 0xffff);
            }
        }
        return image;
    }

    // Format_RGBA8888: horizontal gradient, vertical gradient and deterministic
    // noise; opaque alpha keeps the measurement focused on the colour path.
    for (int y = 0; y < height; ++y) {
        uchar* line = image.scanLine(y);
        quint32 state = seed ^ quint32(y * 2654435761u);
        const int greenBase = (y * 255) / std::max(1, height - 1);
        for (int x = 0; x < width; ++x) {
            state = state * 1664525u + 1013904223u;
            const int noise = int((state >> 24) & 0x1f) - 16;
            const int redBase = (x * 255) / std::max(1, width - 1);
            line[x * 4 + 0] = uchar(std::clamp(redBase + noise, 0, 255));
            line[x * 4 + 1] = uchar(std::clamp(greenBase + (noise / 2), 0, 255));
            line[x * 4 + 2] = uchar(std::clamp(int((state >> 8) & 0xff), 0, 255));
            line[x * 4 + 3] = 255;
        }
    }
    return image;
}

Stats summarize(std::vector<double> samples)
{
    Stats stats;
    if (samples.empty())
        return stats;
    std::sort(samples.begin(), samples.end());
    stats.runs = int(samples.size());
    stats.min = samples.front();
    stats.max = samples.back();
    const auto percentile = [&samples](double p) {
        if (samples.size() == 1)
            return samples.front();
        const double position = (p / 100.0) * double(samples.size() - 1);
        const auto low = size_t(std::floor(position));
        const auto high = size_t(std::ceil(position));
        const double fraction = position - double(low);
        return samples[low] + (samples[high] - samples[low]) * fraction;
    };
    stats.median = percentile(50.0);
    stats.p95 = percentile(95.0);
    return stats;
}

Stats measure(int runs, const std::function<void()>& operation)
{
    operation(); // Warm caches and allocator paths; not included in the stats.
    std::vector<double> samples;
    samples.reserve(size_t(std::max(1, runs)));
    for (int i = 0; i < runs; ++i) {
        QElapsedTimer timer;
        timer.start();
        operation();
        samples.push_back(double(timer.nsecsElapsed()) / 1.0e6);
    }
    return summarize(std::move(samples));
}

void consume(const QImage& image)
{
    if (!image.isNull())
        g_sink.fetch_add(quint64(image.sizeInBytes()) ^ quint64(image.cacheKey()),
                         std::memory_order_relaxed);
}

// Runs independent measurement cases through the global thread pool. Each
// future owns its own source snapshot (QImage is implicitly shared) and each
// case remains single-threaded internally.
QVector<Row> runJobs(const QVector<std::function<QVector<Row>()>>& jobs)
{
    QVector<QFuture<QVector<Row>>> futures;
    futures.reserve(jobs.size());
    for (const auto& job : jobs)
        futures.append(QtConcurrent::run(job));
    QVector<Row> rows;
    for (auto& future : futures) {
        const auto part = future.result();
        rows.append(part);
    }
    return rows;
}

Row timedRow(const QString& suite, const QString& caseName, const QString& format,
             const SizeSpec& size, qint64 sourceBytes, qint64 resultBytes, const Stats& stats,
             const QString& note = {})
{
    Row row;
    row.suite = suite;
    row.caseName = caseName;
    row.format = format;
    row.sizeLabel = size.label;
    row.width = size.width;
    row.height = size.height;
    row.runs = stats.runs;
    row.minMs = stats.min;
    row.medianMs = stats.median;
    row.p95Ms = stats.p95;
    row.maxMs = stats.max;
    row.sourceBytes = sourceBytes;
    row.resultBytes = resultBytes;
    row.note = note;
    return row;
}

Row skippedRow(const QString& suite, const QString& caseName, const QString& format,
               const SizeSpec& size, const QString& reason)
{
    Row row;
    row.suite = suite;
    row.caseName = caseName;
    row.format = format;
    row.sizeLabel = size.label;
    row.width = size.width;
    row.height = size.height;
    row.skipped = true;
    row.note = QStringLiteral("skipped: %1").arg(reason);
    return row;
}

QString estimateReason(qint64 estimatedBytes)
{
    return QStringLiteral("estimated peak %1 MiB exceeds the %2 MiB hard cap")
        .arg(estimatedBytes / miB)
        .arg(hardMemoryCap / miB);
}

QString csvEscape(const QString& value)
{
    if (!value.contains(QLatin1Char(',')) && !value.contains(QLatin1Char('"')) &&
        !value.contains(QLatin1Char('\n'))) {
        return value;
    }
    QString escaped = value;
    escaped.replace(QLatin1Char('"'), QStringLiteral("\"\""));
    return QLatin1Char('"') + escaped + QLatin1Char('"');
}

QString csvField(double value, bool present)
{
    return present ? QString::number(value, 'f', 4) : QString();
}

void printTimedTable(QTextStream& out, const QString& title, const QVector<Row>& rows)
{
    out << "\n### " << title << "\n\n";
    out << "| Size | Format | Case | Runs | Min ms | Median ms | p95 ms | Max ms | Source MB | "
           "Result MB | Notes |\n";
    out << "| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |\n";
    for (const auto& row : rows) {
        out << "| " << row.sizeLabel << " | " << row.format << " | " << row.caseName << " | "
            << (row.skipped ? QStringLiteral("0") : QString::number(row.runs)) << " | "
            << formatMs(row.skipped ? -1.0 : row.minMs) << " | "
            << formatMs(row.skipped ? -1.0 : row.medianMs) << " | "
            << formatMs(row.skipped ? -1.0 : row.p95Ms) << " | "
            << formatMs(row.skipped ? -1.0 : row.maxMs) << " | " << formatMb(row.sourceBytes)
            << " | " << formatMb(row.resultBytes) << " | " << row.note << " |\n";
    }
}

void printMemoryTable(QTextStream& out, const QVector<Row>& rows)
{
    out << "\n### Memory accounting (QImage::sizeInBytes)\n\n";
    out << "Accounting model only, not process RSS. Base is the imported image; rendered is the "
           "authoritative RGBA64 result. Undo capacity uses the production 256 MiB history "
           "budget.\n\n";
    out << "| Size | Source format | Base MB | Rendered MB | Undo snapshots retained | Accounted "
           "peak MB | Notes |\n";
    out << "| --- | --- | ---: | ---: | ---: | ---: | --- |\n";
    for (const auto& row : rows) {
        out << "| " << row.sizeLabel << " | " << row.format << " | " << formatMb(row.sourceBytes)
            << " | " << formatMb(row.resultBytes) << " | " << row.undoEntries << " | "
            << formatMb(row.accountedPeakBytes) << " | " << row.note << " |\n";
    }
}

bool writeCsv(const QString& path, const QVector<Row>& rows)
{
    QFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text | QIODevice::Truncate))
        return false;
    QTextStream out(&file);
    out << "suite,case,format,size,width,height,runs,min_ms,median_ms,p95_ms,max_ms,"
           "source_bytes,result_bytes,undo_entries,accounted_peak_bytes,skipped,note\n";
    for (const auto& row : rows) {
        const bool timing = !row.skipped && row.runs > 0;
        out << csvEscape(row.suite) << ',' << csvEscape(row.caseName) << ','
            << csvEscape(row.format) << ',' << csvEscape(row.sizeLabel) << ',' << row.width << ','
            << row.height << ',' << row.runs << ',' << csvField(row.minMs, timing) << ','
            << csvField(row.medianMs, timing) << ',' << csvField(row.p95Ms, timing) << ','
            << csvField(row.maxMs, timing) << ',' << row.sourceBytes << ',' << row.resultBytes
            << ',' << row.undoEntries << ',' << row.accountedPeakBytes << ','
            << (row.skipped ? 1 : 0) << ',' << csvEscape(row.note) << '\n';
    }
    out.flush();
    return true;
}

QJsonObject rowToJson(const Row& row)
{
    QJsonObject object;
    object.insert(QStringLiteral("suite"), row.suite);
    object.insert(QStringLiteral("case"), row.caseName);
    object.insert(QStringLiteral("format"), row.format);
    object.insert(QStringLiteral("size"), row.sizeLabel);
    object.insert(QStringLiteral("width"), row.width);
    object.insert(QStringLiteral("height"), row.height);
    object.insert(QStringLiteral("runs"), row.runs);
    if (!row.skipped && row.runs > 0) {
        object.insert(QStringLiteral("min_ms"), row.minMs);
        object.insert(QStringLiteral("median_ms"), row.medianMs);
        object.insert(QStringLiteral("p95_ms"), row.p95Ms);
        object.insert(QStringLiteral("max_ms"), row.maxMs);
    }
    object.insert(QStringLiteral("source_bytes"), double(row.sourceBytes));
    object.insert(QStringLiteral("result_bytes"), double(row.resultBytes));
    if (row.undoEntries >= 0)
        object.insert(QStringLiteral("undo_entries"), double(row.undoEntries));
    if (row.accountedPeakBytes >= 0)
        object.insert(QStringLiteral("accounted_peak_bytes"), double(row.accountedPeakBytes));
    object.insert(QStringLiteral("skipped"), row.skipped);
    if (!row.note.isEmpty())
        object.insert(QStringLiteral("note"), row.note);
    return object;
}

bool writeJson(const QString& path, const Options& options, const Environment& environment,
               const QVector<SizeSpec>& sizes, const QVector<Row>& rows)
{
    QJsonObject root;
    QJsonObject env;
    env.insert(QStringLiteral("cpu"), environment.cpu);
    env.insert(QStringLiteral("logical_cores"), environment.logicalCores);
    env.insert(QStringLiteral("memory"), environment.memory);
    env.insert(QStringLiteral("os"), environment.os);
    env.insert(QStringLiteral("qt_runtime"), environment.qtRuntime);
    env.insert(QStringLiteral("qt_built"), environment.qtBuilt);
    env.insert(QStringLiteral("compiler"), environment.compiler);
    env.insert(QStringLiteral("build"), environment.build);
    env.insert(QStringLiteral("load_average"), environment.load);
    root.insert(QStringLiteral("environment"), env);

    QJsonObject run;
    run.insert(QStringLiteral("mode"),
               options.quick ? QStringLiteral("quick") : QStringLiteral("full"));
    run.insert(QStringLiteral("runs"), options.runs);
    run.insert(QStringLiteral("warmup"), 1);
    run.insert(QStringLiteral("concurrent_adjustment_cases"),
               options.jobs > 0 ? options.jobs : std::clamp(QThread::idealThreadCount(), 1, 8));
    QJsonArray sizeArray;
    for (const auto& size : sizes) {
        QJsonObject entry;
        entry.insert(QStringLiteral("label"), size.label);
        entry.insert(QStringLiteral("width"), size.width);
        entry.insert(QStringLiteral("height"), size.height);
        sizeArray.append(entry);
    }
    run.insert(QStringLiteral("sizes"), sizeArray);
    root.insert(QStringLiteral("run"), run);

    QJsonArray resultArray;
    for (const auto& row : rows)
        resultArray.append(rowToJson(row));
    root.insert(QStringLiteral("results"), resultArray);

    QFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text | QIODevice::Truncate))
        return false;
    file.write(QJsonDocument(root).toJson(QJsonDocument::Indented));
    return true;
}

// Advisory ceilings used by --check. They are intentionally looser than the
// product targets documented in docs/performance.md so that shared-host noise
// does not turn the harness into a flaky gate.
struct Budget
{
    QString suite;
    QString caseNameContains;
    QString formatContains;
    QString sizeLabel;
    double p95Ms;
    QString rationale;
};

QVector<Budget> budgets()
{
    // These are regression ceilings, not product targets. They are deliberately
    // generous so that a busy shared host does not make --check flaky. The
    // aspirational product targets live in docs/performance.md.
    return {
        {QStringLiteral("filter-previews"), QStringLiteral("batch"), QStringLiteral("RGBA8888"),
         QStringLiteral("2 MP"), 60.0,
         QStringLiteral("regression ceiling; product target <= 16 ms per batch")},
        {QStringLiteral("interaction"), QStringLiteral("first preview"), QStringLiteral("RGBA8888"),
         QStringLiteral("2 MP"), 500.0,
         QStringLiteral("regression ceiling; product target <= 33 ms on the GPU path")},
        {QStringLiteral("adjustments"), QStringLiteral("exposure +1"), QStringLiteral("RGBA8888"),
         QStringLiteral("2 MP"), 800.0,
         QStringLiteral("regression ceiling; product target <= 33 ms for an interactive preview")},
        {QStringLiteral("decode"), QStringLiteral("JPEG"), QString(), QString(), 150.0,
         QStringLiteral("regression ceiling; warm import target <= 100 ms")},
    };
}

struct CheckResult
{
    int checked = 0;
    int failed = 0;
};

CheckResult runChecks(QTextStream& out, const QVector<Row>& rows)
{
    CheckResult result;
    out << "\n### Budget checks (advisory)\n\n";
    out << "| Suite | Case | Size | p95 ms | Ceiling ms | Result | Rationale |\n";
    out << "| --- | --- | --- | ---: | ---: | --- | --- |\n";
    for (const auto& budget : budgets()) {
        for (const auto& row : rows) {
            if (row.suite != budget.suite || row.skipped || row.runs == 0)
                continue;
            if (!row.caseName.contains(budget.caseNameContains))
                continue;
            if (!budget.formatContains.isEmpty() && !row.format.contains(budget.formatContains))
                continue;
            if (!budget.sizeLabel.isEmpty() && row.sizeLabel != budget.sizeLabel)
                continue;
            ++result.checked;
            const bool passed = row.p95Ms <= budget.p95Ms;
            if (!passed)
                ++result.failed;
            out << "| " << row.suite << " | " << row.caseName << " | " << row.sizeLabel << " | "
                << formatMs(row.p95Ms) << " | " << formatMs(budget.p95Ms) << " | "
                << (passed ? QStringLiteral("PASS") : QStringLiteral("FAIL")) << " | "
                << budget.rationale << " |\n";
        }
    }
    if (result.checked == 0)
        out << "| - | - | - | - | - | SKIP | no matching rows in this mode |\n";
    return result;
}

void printUsage(QTextStream& out)
{
    out << "Usage: bench_pipeline [options]\n\n"
           "  --quick        Use smaller image sizes (smoke mode)\n"
           "  --runs N       Measured runs after one warmup (default 5, minimum 5)\n"
           "  --jobs N       Concurrent independent cases (default auto, max 8; 1 = serial)\n"
           "  --csv PATH     Write machine-readable CSV\n"
           "  --json PATH    Write machine-readable JSON\n"
           "  --check        Compare advisory regression ceilings and exit non-zero on failure\n"
           "  -h, --help     Show this help\n";
}

struct AdjustmentCase
{
    QString name;
    NekoPic::Adjustments::Parameters parameters;
    bool identity = false;
};

QVector<AdjustmentCase> adjustmentCases()
{
    using Parameters = NekoPic::Adjustments::Parameters;
    QVector<AdjustmentCase> cases;
    cases.append({QStringLiteral("identity"), Parameters{}, true});
    {
        Parameters p;
        p.exposure = 1.0;
        cases.append({QStringLiteral("exposure +1"), p, false});
    }
    {
        Parameters p;
        p.exposure = 2.0;
        p.contrast = 0.2;
        cases.append({QStringLiteral("exposure +2 contrast"), p, false});
    }
    {
        Parameters p;
        p.saturation = -1.0;
        cases.append({QStringLiteral("saturation -1"), p, false});
    }
    {
        Parameters p;
        p.filterPreset = QStringLiteral("mono");
        p.filterIntensity = 1.0;
        cases.append({QStringLiteral("mono filter"), p, false});
    }
    {
        Parameters p;
        p.exposure = 1.2;
        p.saturation = 0.3;
        p.filterPreset = QStringLiteral("vintage");
        p.filterIntensity = 0.7;
        cases.append({QStringLiteral("combined filter + intensity"), p, false});
    }
    {
        Parameters p;
        p.highlights = 0.5;
        p.shadows = -0.5;
        cases.append({QStringLiteral("highlights + shadows"), p, false});
    }
    {
        Parameters p;
        p.whites = 0.4;
        p.blacks = -0.4;
        cases.append({QStringLiteral("whites + blacks"), p, false});
    }
    {
        Parameters p;
        p.temperature = 0.4;
        p.tint = -0.2;
        cases.append({QStringLiteral("temperature + tint"), p, false});
    }
    {
        Parameters p;
        p.vibrance = 0.5;
        cases.append({QStringLiteral("vibrance +0.5"), p, false});
    }
    {
        Parameters p;
        p.hsl[0].hue = 0.3;
        p.hsl[0].saturation = 0.3;
        cases.append({QStringLiteral("HSL red shift"), p, false});
    }
    {
        Parameters p;
        p.curves[0].points = {0.0, 0.17, 0.5, 0.83, 1.0};
        cases.append({QStringLiteral("RGB S-curve"), p, false});
    }
    {
        Parameters p;
        p.grade[0] = {220.0, 0.5, -0.2};
        p.gradeBlending = 0.5;
        cases.append({QStringLiteral("grade shadows"), p, false});
    }
    {
        Parameters p;
        p.texture = 0.3;
        p.clarity = 0.5;
        p.sharpen = 0.5;
        cases.append({QStringLiteral("texture + clarity + sharpen"), p, false});
    }
    {
        Parameters p;
        p.vignette = -0.5;
        p.feather = 0.5;
        p.grain = 0.2;
        p.fade = 0.2;
        cases.append({QStringLiteral("vignette + grain + fade"), p, false});
    }
    {
        Parameters p;
        p.highlights = 0.3;
        p.shadows = -0.3;
        p.temperature = 0.2;
        p.vibrance = 0.3;
        p.hsl[4].saturation = 0.2;
        p.curves[0].points = {0.0, 0.2, 0.5, 0.8, 1.0};
        p.grade[1] = {35.0, 0.2, 0.0};
        p.clarity = 0.2;
        p.vignette = -0.2;
        cases.append({QStringLiteral("extended combined"), p, false});
    }
    return cases;
}

QVector<SizeSpec> sizeSpecs(bool quick)
{
    if (quick) {
        return {
            {QStringLiteral("0.5 MP"), 816, 612},
            {QStringLiteral("2 MP"), 1800, 1200},
            {QStringLiteral("8 MP"), 3264, 2448},
        };
    }
    return {
        {QStringLiteral("2 MP"), 1920, 1080},
        {QStringLiteral("12 MP"), 4000, 3000},
        {QStringLiteral("48 MP"), 8000, 6000},
    };
}

} // namespace

int main(int argc, char** argv)
{
    QCoreApplication app(argc, argv);

    Options options;
    for (int index = 1; index < argc; ++index) {
        const QString argument = QString::fromLocal8Bit(argv[index]);
        if (argument == QStringLiteral("--quick")) {
            options.quick = true;
        } else if (argument == QStringLiteral("--check")) {
            options.check = true;
        } else if (argument == QStringLiteral("--csv") ||
                   argument.startsWith(QStringLiteral("--csv="))) {
            if (argument.contains(QLatin1Char('=')))
                options.csvPath = argument.section(QLatin1Char('='), 1);
            else if (++index < argc)
                options.csvPath = QString::fromLocal8Bit(argv[index]);
            else {
                QTextStream(stderr) << "--csv requires a path\n";
                return 2;
            }
        } else if (argument == QStringLiteral("--json") ||
                   argument.startsWith(QStringLiteral("--json="))) {
            if (argument.contains(QLatin1Char('=')))
                options.jsonPath = argument.section(QLatin1Char('='), 1);
            else if (++index < argc)
                options.jsonPath = QString::fromLocal8Bit(argv[index]);
            else {
                QTextStream(stderr) << "--json requires a path\n";
                return 2;
            }
        } else if (argument == QStringLiteral("--runs") ||
                   argument.startsWith(QStringLiteral("--runs="))) {
            QString value;
            if (argument.contains(QLatin1Char('=')))
                value = argument.section(QLatin1Char('='), 1);
            else if (++index < argc)
                value = QString::fromLocal8Bit(argv[index]);
            bool ok = false;
            const int runs = value.toInt(&ok);
            if (!ok || runs < 1) {
                QTextStream(stderr) << "--runs requires a positive integer\n";
                return 2;
            }
            options.runs = runs;
        } else if (argument == QStringLiteral("--jobs") ||
                   argument.startsWith(QStringLiteral("--jobs="))) {
            QString value;
            if (argument.contains(QLatin1Char('=')))
                value = argument.section(QLatin1Char('='), 1);
            else if (++index < argc)
                value = QString::fromLocal8Bit(argv[index]);
            bool ok = false;
            const int jobs = value.toInt(&ok);
            if (!ok || jobs < 1) {
                QTextStream(stderr) << "--jobs requires a positive integer\n";
                return 2;
            }
            options.jobs = jobs;
        } else if (argument == QStringLiteral("-h") || argument == QStringLiteral("--help")) {
            QTextStream out(stdout);
            printUsage(out);
            out.flush();
            return 0;
        } else {
            QTextStream(stderr) << "Unknown option: " << argument << "\n";
            return 2;
        }
    }
    if (options.runs < 5) {
        QTextStream(stderr) << "warning: --runs " << options.runs
                            << " is below the documented minimum of 5 warm runs\n";
    }

    const auto environment = gatherEnvironment();
    const auto sizes = sizeSpecs(options.quick);
    const auto cases = adjustmentCases();
    const auto historyBudget = qint64(NekoPic::Document::HistoryStore::DefaultBudgetBytes);

    const int workerCount =
        options.jobs > 0 ? options.jobs : std::clamp(QThread::idealThreadCount(), 1, 8);
    QThreadPool::globalInstance()->setMaxThreadCount(workerCount);

    QVector<Row> filterPreviews;
    QVector<Row> mosaic;
    QVector<Row> interaction;
    QVector<Row> previewMath;
    QVector<Row> decode;
    QVector<Row> memory;
    QHash<QString, Row> fullSizeReference;

    // --- 1. Adjustments matrix ------------------------------------------------
    // Independent (size, format, case) measurements are queued through the
    // thread pool. Each individual case is still a single-threaded loop; this
    // is what keeps the 48 MP matrix inside the ~2 minute budget.
    QVector<std::function<QVector<Row>()>> adjustmentJobs;
    for (const auto& size : sizes) {
        const qint64 pixels = qint64(size.width) * qint64(size.height);
        for (const bool rgba64 : {false, true}) {
            const auto format = rgba64 ? QImage::Format_RGBA64 : QImage::Format_RGBA8888;
            const QString formatName =
                rgba64 ? QStringLiteral("RGBA64") : QStringLiteral("RGBA8888");
            const qint64 estimate = pixels * (rgba64 ? 16 : 12) + 64 * miB;
            if (estimate > hardMemoryCap) {
                const QString reason = estimateReason(estimate);
                adjustmentJobs.append([cases, size, formatName, reason] {
                    QVector<Row> rows;
                    for (const auto& testCase : cases)
                        rows.append(skippedRow(QStringLiteral("adjustments"), testCase.name,
                                               formatName, size, reason));
                    return rows;
                });
                continue;
            }
            const QImage source = makeSyntheticImage(size.width, size.height, format, 0x9e3779b9u);
            if (source.isNull()) {
                const QString reason = QStringLiteral("synthetic image allocation failed");
                adjustmentJobs.append([cases, size, formatName, reason] {
                    QVector<Row> rows;
                    for (const auto& testCase : cases)
                        rows.append(skippedRow(QStringLiteral("adjustments"), testCase.name,
                                               formatName, size, reason));
                    return rows;
                });
                continue;
            }
            const qint64 sourceBytes = source.sizeInBytes();
            for (const auto& testCase : cases) {
                adjustmentJobs.append(
                    [size, formatName, source, sourceBytes, pixels, testCase, runs = options.runs] {
                        const auto stats = measure(runs, [&source, &testCase] {
                            consume(NekoPic::Adjustments::apply(source, testCase.parameters));
                        });
                        const qint64 resultBytes = testCase.identity ? sourceBytes : pixels * 8;
                        return QVector<Row>{timedRow(QStringLiteral("adjustments"), testCase.name,
                                                     formatName, size, sourceBytes, resultBytes,
                                                     stats)};
                    });
            }
        }
    }
    const QVector<Row> adjustments = runJobs(adjustmentJobs);
    for (const auto& row : adjustments) {
        if (row.format == QStringLiteral("RGBA8888") &&
            row.caseName == QStringLiteral("exposure +2 contrast") && !row.skipped) {
            fullSizeReference.insert(row.sizeLabel, row);
        }
    }

    // --- 2. Filter preview batch equivalent ----------------------------------
    for (const auto& size : sizes) {
        const qint64 estimate = qint64(size.width) * qint64(size.height) * 4 + 16 * miB;
        if (estimate > hardMemoryCap) {
            filterPreviews.append(skippedRow(
                QStringLiteral("filter-previews"), QStringLiteral("batch (downscale + 13 presets)"),
                QStringLiteral("RGBA8888"), size, estimateReason(estimate)));
            continue;
        }
        const QImage source =
            makeSyntheticImage(size.width, size.height, QImage::Format_RGBA8888, 0x51ed270bu);
        if (source.isNull()) {
            filterPreviews.append(skippedRow(QStringLiteral("filter-previews"),
                                             QStringLiteral("batch (downscale + 13 presets)"),
                                             QStringLiteral("RGBA8888"), size,
                                             QStringLiteral("synthetic image allocation failed")));
            continue;
        }
        const auto smallSize = source.size().scaled(QSize(192, 144), Qt::KeepAspectRatio);
        const auto presetIds = NekoPic::Filters::presetIds();
        NekoPic::Adjustments::Parameters parameters;
        parameters.exposure = 2.0;
        parameters.contrast = 0.2;
        const auto operation = [&source, &parameters, presetIds] {
            const auto small =
                (source.width() > 192 || source.height() > 144)
                    ? source.scaled(192, 144, Qt::KeepAspectRatio, Qt::SmoothTransformation)
                    : source;
            for (const auto &preset : presetIds) {
                auto tileParameters = parameters;
                tileParameters.filterPreset = preset;
                consume(NekoPic::Adjustments::apply(small, tileParameters)
                            .convertToFormat(QImage::Format_RGBA8888));
            }
        };
        const auto stats = measure(options.runs, operation);
        const qint64 resultBytes = qint64(smallSize.width()) * smallSize.height() * 4
            * presetIds.size();
        const QString note = QStringLiteral("batch = smooth downscale to %1x%2 + %3 presets; "
                                            "per-thumbnail median %4 ms")
                                 .arg(smallSize.width())
                                 .arg(smallSize.height())
                                 .arg(presetIds.size())
                                 .arg(formatMs(stats.median / double(presetIds.size())));
        filterPreviews.append(timedRow(
            QStringLiteral("filter-previews"), QStringLiteral("batch (downscale + 13 presets)"),
            QStringLiteral("RGBA8888"), size, source.sizeInBytes(), resultBytes, stats, note));
    }

    // --- 3. Mosaic rectangle and stroke on 12 MP ------------------------------
    {
        const SizeSpec mosaicSize{QStringLiteral("12 MP"), 4000, 3000};
        const QRect rectangle(1400, 1000, 1200, 900);
        for (const bool rgba64 : {false, true}) {
            const auto format = rgba64 ? QImage::Format_RGBA64 : QImage::Format_RGBA8888;
            const QString formatName =
                rgba64 ? QStringLiteral("RGBA64") : QStringLiteral("RGBA8888");
            const QImage source =
                makeSyntheticImage(mosaicSize.width, mosaicSize.height, format, 0x27d4eb2du);
            if (source.isNull()) {
                mosaic.append(skippedRow(QStringLiteral("mosaic"), QStringLiteral("rectangle"),
                                         formatName, mosaicSize,
                                         QStringLiteral("synthetic image allocation failed")));
                continue;
            }
            const qint64 estimate = source.sizeInBytes() * 2 +
                                    qint64(rectangle.width()) * rectangle.height() * 4 + 32 * miB;
            if (estimate > hardMemoryCap) {
                mosaic.append(skippedRow(QStringLiteral("mosaic"), QStringLiteral("rectangle"),
                                         formatName, mosaicSize, estimateReason(estimate)));
                continue;
            }
            const QVector<int> blockSizes = rgba64 ? QVector<int>{32} : QVector<int>{8, 32, 128};
            for (const int blockSize : blockSizes) {
                const auto stats = measure(options.runs, [&source, &rectangle, blockSize] {
                    consume(NekoPic::Mosaic::pixelateRect(source, rectangle, blockSize));
                });
                mosaic.append(timedRow(
                    QStringLiteral("mosaic"), QStringLiteral("rectangle block %1").arg(blockSize),
                    formatName, mosaicSize, source.sizeInBytes(), source.sizeInBytes(), stats,
                    QStringLiteral("ROI 1200x900 (9% of image)")));
            }

            NekoPic::Mosaic::Stroke stroke;
            stroke.diameter = 96.0;
            for (int point = 0; point < 64; ++point) {
                const double t = double(point) / 63.0;
                stroke.points.append(
                    QPointF(1000.0 + t * 2000.0, 1500.0 + 400.0 * std::sin(t * 6.283185307179586)));
            }
            const QVector<int> strokeBlocks = rgba64 ? QVector<int>{32} : QVector<int>{8, 32, 128};
            for (const int blockSize : strokeBlocks) {
                const auto stats = measure(options.runs, [&source, &stroke, blockSize] {
                    consume(NekoPic::Mosaic::pixelateStroke(source, stroke, blockSize));
                });
                mosaic.append(timedRow(
                    QStringLiteral("mosaic"), QStringLiteral("stroke block %1").arg(blockSize),
                    formatName, mosaicSize, source.sizeInBytes(), source.sizeInBytes(), stats,
                    QStringLiteral("64 points, diameter 96, ROI approx 2200x1000")));
            }
        }
    }

    // --- 4. Interaction latency proxies --------------------------------------
    {
        NekoPic::Adjustments::Parameters parameters;
        parameters.exposure = 2.0;
        parameters.contrast = 0.2;
        for (const auto& size : sizes) {
            const QImage source =
                makeSyntheticImage(size.width, size.height, QImage::Format_RGBA8888, 0x68e31da4u);
            if (source.isNull()) {
                interaction.append(skippedRow(QStringLiteral("interaction"),
                                              QStringLiteral("first preview 1600x1000"),
                                              QStringLiteral("RGBA8888"), size,
                                              QStringLiteral("synthetic image allocation failed")));
                continue;
            }
            const qint64 estimate = source.sizeInBytes() + 1600LL * 1000LL * 8 + 32 * miB;
            if (estimate > hardMemoryCap) {
                interaction.append(skippedRow(
                    QStringLiteral("interaction"), QStringLiteral("first preview 1600x1000"),
                    QStringLiteral("RGBA8888"), size, estimateReason(estimate)));
                continue;
            }
            const auto operation = [&source, &parameters] {
                const auto preview =
                    source.scaled(1600, 1000, Qt::KeepAspectRatio, Qt::SmoothTransformation);
                consume(NekoPic::Adjustments::apply(preview, parameters));
            };
            const auto stats = measure(options.runs, operation);
            const auto previewSize = source.size().scaled(QSize(1600, 1000), Qt::KeepAspectRatio);
            const qint64 resultBytes = qint64(previewSize.width()) * previewSize.height() * 8;
            interaction.append(
                timedRow(QStringLiteral("interaction"), QStringLiteral("first preview 1600x1000"),
                         QStringLiteral("RGBA8888"), size, source.sizeInBytes(), resultBytes, stats,
                         QStringLiteral("downscale + apply; proposed display-scale proxy")));
            if (fullSizeReference.contains(size.label)) {
                auto reference = fullSizeReference.value(size.label);
                reference.note = QStringLiteral("full-size authoritative render, same parameters");
                interaction.append(reference);
            }
        }

        // QtConcurrent round trip on the largest available size (12 MP in full mode).
        const SizeSpec queueSize = (sizes.size() >= 2) ? sizes.at(sizes.size() - 2) : sizes.last();
        const QImage source = makeSyntheticImage(queueSize.width, queueSize.height,
                                                 QImage::Format_RGBA8888, 0x1b56c4e9u);
        if (!source.isNull()) {
            const auto operation = [&source, &parameters] {
                QFutureWatcher<QImage> watcher;
                QEventLoop loop;
                QObject::connect(&watcher, &QFutureWatcherBase::finished, &loop, &QEventLoop::quit);
                watcher.setFuture(QtConcurrent::run([source, parameters] {
                    return NekoPic::Adjustments::apply(source, parameters);
                }));
                loop.exec();
                consume(watcher.result());
            };
            const auto stats = measure(options.runs, operation);
            interaction.append(timedRow(
                QStringLiteral("interaction"), QStringLiteral("QtConcurrent dispatch + result"),
                QStringLiteral("RGBA8888"), queueSize, source.sizeInBytes(),
                qint64(queueSize.width) * queueSize.height * 8, stats,
                QStringLiteral("thread handoff + event-loop delivery; excludes UI debounce")));
        }
    }

    // --- 5. GPU preview CPU mirror at 2 MP ------------------------------------
    {
        const SizeSpec size{QStringLiteral("2 MP"), 1920, 1080};
        NekoPic::Adjustments::Parameters parameters;
        parameters.exposure = 1.0;
        parameters.contrast = 0.2;
        parameters.saturation = -0.2;
        const QImage source8 =
            makeSyntheticImage(size.width, size.height, QImage::Format_RGBA8888, 0x7f4a7c15u);
        if (!source8.isNull()) {
            const auto authoritative = measure(options.runs, [&source8, &parameters] {
                consume(NekoPic::Adjustments::apply(source8, parameters));
            });
            previewMath.append(timedRow(QStringLiteral("preview-math"),
                                        QStringLiteral("authoritative CPU apply"),
                                        QStringLiteral("RGBA8888 -> RGBA64"), size,
                                        source8.sizeInBytes(), qint64(size.width) * size.height * 8,
                                        authoritative, QStringLiteral("export/commit path")));
            const auto mirror = measure(options.runs, [&source8, &parameters] {
                consume(NekoPic::Render::PreviewMath::applyRgba8(source8, parameters));
            });
            previewMath.append(
                timedRow(QStringLiteral("preview-math"), QStringLiteral("shader CPU mirror"),
                         QStringLiteral("RGBA8888"), size, source8.sizeInBytes(),
                         qint64(size.width) * size.height * 4, mirror,
                         QStringLiteral("CPU stand-in for the GPU shader; not used for export")));
        }
        const QImage source64 =
            makeSyntheticImage(size.width, size.height, QImage::Format_RGBA64, 0x2545f491u);
        if (!source64.isNull()) {
            const auto authoritative = measure(options.runs, [&source64, &parameters] {
                consume(NekoPic::Adjustments::apply(source64, parameters));
            });
            previewMath.append(timedRow(QStringLiteral("preview-math"),
                                        QStringLiteral("authoritative CPU apply"),
                                        QStringLiteral("RGBA64"), size, source64.sizeInBytes(),
                                        qint64(size.width) * size.height * 8, authoritative,
                                        QStringLiteral("export/commit path")));
            const auto mirror = measure(options.runs, [&source64, &parameters] {
                consume(NekoPic::Render::PreviewMath::applyRgba64(source64, parameters));
            });
            previewMath.append(
                timedRow(QStringLiteral("preview-math"), QStringLiteral("shader CPU mirror"),
                         QStringLiteral("RGBA64"), size, source64.sizeInBytes(),
                         qint64(size.width) * size.height * 8, mirror,
                         QStringLiteral("CPU stand-in for the GPU shader; not used for export")));
        }
    }

    // --- 6. Import/decode timing for the bundled demo image -------------------
    {
        const QString demoPath = QDir::cleanPath(QStringLiteral(NEKOPIC_BENCH_SOURCE_DIR) +
                                                 QStringLiteral("/../assets/demo.jpg"));
        const SizeSpec unknownSize{QStringLiteral("demo.jpg"), 0, 0};
        if (!QFileInfo::exists(demoPath)) {
            decode.append(
                skippedRow(QStringLiteral("decode"), QStringLiteral("bundled JPEG"),
                           QStringLiteral("QImageReader"), unknownSize,
                           QStringLiteral("assets/demo.jpg not found at %1").arg(demoPath)));
        } else {
            const auto probe = NekoPic::ImageIO::load(demoPath);
            if (probe.image.isNull()) {
                decode.append(skippedRow(QStringLiteral("decode"), QStringLiteral("bundled JPEG"),
                                         QStringLiteral("QImageReader"), unknownSize,
                                         QStringLiteral("decode failed: %1").arg(probe.error)));
            } else {
                const SizeSpec demoSize{QStringLiteral("1800x1200"), probe.image.width(),
                                        probe.image.height()};
                const auto stats = measure(options.runs, [&demoPath] {
                    const auto result = NekoPic::ImageIO::load(demoPath);
                    if (!result.image.isNull())
                        g_sink.fetch_add(quint64(result.image.sizeInBytes()),
                                         std::memory_order_relaxed);
                });
                decode.append(
                    timedRow(QStringLiteral("decode"), QStringLiteral("bundled JPEG"),
                             QStringLiteral("QImageReader"), demoSize, probe.image.sizeInBytes(),
                             probe.image.sizeInBytes(), stats,
                             QStringLiteral("warm file cache; %1 KiB file; cold disk not measured")
                                 .arg(QFileInfo(demoPath).size() / 1024)));
            }
        }
    }

    // --- Memory accounting ----------------------------------------------------
    {
        for (const auto& size : sizes) {
            const qint64 pixels = qint64(size.width) * qint64(size.height);
            for (const bool rgba64 : {false, true}) {
                Row row;
                row.suite = QStringLiteral("memory");
                row.caseName = QStringLiteral("base + rendered + undo snapshots");
                row.format = rgba64 ? QStringLiteral("RGBA64") : QStringLiteral("RGBA8888");
                row.sizeLabel = size.label;
                row.width = size.width;
                row.height = size.height;
                row.sourceBytes = pixels * (rgba64 ? 8 : 4);
                row.resultBytes = pixels * 8;
                const qint64 held = row.sourceBytes >= historyBudget
                                        ? 0
                                        : (historyBudget - row.sourceBytes) / row.resultBytes;
                row.undoEntries = held;
                row.accountedPeakBytes =
                    row.sourceBytes + std::max<qint64>(1, held) * row.resultBytes;
                row.note = held == 0
                               ? QStringLiteral("base + one render already exceeds the history "
                                                "budget; no undo snapshot retained")
                               : QStringLiteral(
                                     "history can retain %1 rendered snapshot(s) within 256 MiB")
                                     .arg(held);
                memory.append(row);
            }
        }
    }

    // --- Output ---------------------------------------------------------------
    QVector<Row> allRows;
    const auto appendAll = [&allRows](const QVector<Row>& rows) {
        for (const auto& row : rows)
            allRows.append(row);
    };
    appendAll(adjustments);
    appendAll(filterPreviews);
    appendAll(mosaic);
    appendAll(interaction);
    appendAll(previewMath);
    appendAll(decode);
    appendAll(memory);

    QTextStream out(stdout);
    out << "# NekoPic pipeline benchmark\n\n";
    out << "Mode: **" << (options.quick ? "quick" : "full") << "**, one warmup + " << options.runs
        << " measured runs per case.\n\n";
    out << environment.markdown();
    out << QStringLiteral("- **Adjustment concurrency**: up to %1 independent cases at once "
                          "(each case single-threaded; `--jobs 1` for serial)\n")
               .arg(workerCount);
    out << "\n> Shared-host caveat: these are wall-clock numbers from a general-purpose desktop. "
           "CPU frequency scaling, scheduler placement, file cache and background load change the "
           "results; treat medians as indicative and p95 as a tail warning, not as hardware "
           "guarantees. The adjustment matrix runs independent cases concurrently to keep the "
           "48 MP sweep inside the runtime budget, so those values are upper bounds under "
           "all-core load. Run with `--jobs 1` on an otherwise idle machine for isolated "
           "latencies. Other suites run one case at a time.\n";
    out << "\nPercentiles use linear interpolation between sorted samples; with five samples p95 "
           "is close to the maximum. Sizes are synthetic and deterministic (gradient + noise), "
           "generated in-process; only the demo decode reads from disk.\n";

    printTimedTable(out, QStringLiteral("1. Adjustments (NekoPic::Adjustments::apply)"),
                    adjustments);
    printTimedTable(out, QStringLiteral("2. Filter preview batch (192x144, 13 presets)"),
                    filterPreviews);
    printTimedTable(out, QStringLiteral("3. Mosaic (12 MP, moderate area)"), mosaic);
    printTimedTable(out, QStringLiteral("4a. Interaction latency proxies"), interaction);
    printTimedTable(out, QStringLiteral("5. GPU preview CPU mirror vs authoritative CPU"),
                    previewMath);
    printTimedTable(out, QStringLiteral("6. Import/decode"), decode);
    printMemoryTable(out, memory);

    if (!options.csvPath.isEmpty()) {
        if (writeCsv(options.csvPath, allRows))
            out << "\nCSV written to " << options.csvPath << "\n";
        else
            QTextStream(stderr) << "Could not write CSV to " << options.csvPath << "\n";
    }
    if (!options.jsonPath.isEmpty()) {
        if (writeJson(options.jsonPath, options, environment, sizes, allRows))
            out << "JSON written to " << options.jsonPath << "\n";
        else
            QTextStream(stderr) << "Could not write JSON to " << options.jsonPath << "\n";
    }

    int exitCode = 0;
    if (options.check) {
        const auto checks = runChecks(out, allRows);
        out << "\n" << checks.checked << " budget check(s), " << checks.failed << " failure(s).\n";
        if (checks.failed > 0)
            exitCode = 1;
    }

    qint64 skipped = 0;
    for (const auto& row : allRows)
        skipped += row.skipped ? 1 : 0;
    out << "\nCompleted " << allRows.size() << " rows, " << skipped
        << " skipped; sink=" << g_sink.load() << ".\n";
    out.flush();
    return exitCode;
}
