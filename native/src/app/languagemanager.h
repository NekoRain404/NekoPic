#pragma once

#include <QObject>
#include <QTranslator>

class QQmlEngine;

class LanguageManager final : public QObject {
    Q_OBJECT
public:
    explicit LanguageManager(QQmlEngine &engine, QObject *parent = nullptr);
    Q_INVOKABLE void setLanguage(const QString &locale);
private:
    QQmlEngine &engine_;
    QTranslator translator_;
};
