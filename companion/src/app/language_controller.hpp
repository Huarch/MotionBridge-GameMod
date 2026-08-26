#pragma once

#include <QObject>
#include <QString>
#include <QTranslator>

class QGuiApplication;
class QQmlApplicationEngine;

class LanguageController final : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString language READ language NOTIFY languageChanged)
    Q_PROPERTY(QString effectiveLanguage READ effective_language NOTIFY languageChanged)

public:
    explicit LanguageController(QGuiApplication* application, QObject* parent = nullptr);

    [[nodiscard]] QString language() const;
    [[nodiscard]] QString effective_language() const;
    void set_engine(QQmlApplicationEngine* engine);

    Q_INVOKABLE void set_language(const QString& language);

signals:
    void languageChanged();

private:
    static QString normalize(const QString& language);
    void apply();

    QGuiApplication* application_{};
    QQmlApplicationEngine* engine_{};
    QTranslator translator_;
    QString language_{"auto"};
    QString effective_language_{"en"};
};
