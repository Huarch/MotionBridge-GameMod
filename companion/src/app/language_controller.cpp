#include "language_controller.hpp"

#include "companion_settings.hpp"

#include <QGuiApplication>
#include <QLocale>
#include <QQmlApplicationEngine>

LanguageController::LanguageController(QGuiApplication* application, QObject* parent)
    : QObject(parent), application_(application) {
    auto settings = companion_settings();
    language_ = normalize(settings.value("ui/language", "auto").toString());
    apply();
}

QString LanguageController::language() const { return language_; }
QString LanguageController::effective_language() const { return effective_language_; }

void LanguageController::set_engine(QQmlApplicationEngine* engine) { engine_ = engine; }

QString LanguageController::normalize(const QString& language) {
    const auto value = language.trimmed().toLower();
    if (value == u"zh" || value == u"zh_cn" || value == u"chinese") return QStringLiteral("zh_CN");
    if (value == u"en" || value == u"english") return QStringLiteral("en");
    return QStringLiteral("auto");
}

void LanguageController::set_language(const QString& language) {
    const auto normalized = normalize(language);
    if (language_ == normalized) return;
    language_ = normalized;
    auto settings = companion_settings();
    settings.setValue("ui/language", language_);
    settings.sync();
    apply();
    emit languageChanged();
}

void LanguageController::apply() {
    application_->removeTranslator(&translator_);
    effective_language_ = language_ == u"auto"
        ? (QLocale::system().language() == QLocale::Chinese ? QStringLiteral("zh_CN") : QStringLiteral("en"))
        : language_;
    if (effective_language_ == u"zh_CN" && translator_.load(QStringLiteral(":/i18n/companion_zh_CN.qm"))) {
        application_->installTranslator(&translator_);
    }
    if (engine_ != nullptr) engine_->retranslate();
}
