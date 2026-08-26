#include "companion_settings.hpp"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QStandardPaths>

QSettings companion_settings() {
    const auto local_data = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation);
    const auto legacy_directory = QDir(local_data).filePath("FallenDollTCode");
    const auto legacy_path = QDir(legacy_directory).filePath("companion.ini");
    const auto settings_directory = QDir(local_data).filePath("MotionBridge");
    const auto settings_path = QDir(settings_directory).filePath("motion-bridge.ini");
    const auto application_directory = QCoreApplication::applicationDirPath();
    const auto portable = QFileInfo::exists(QDir(application_directory).filePath("portable.mode"));
    if (!portable) {
        QDir().mkpath(settings_directory);
        if (!QFileInfo::exists(settings_path) && QFileInfo::exists(legacy_path)) QFile::copy(legacy_path, settings_path);
        return QSettings(settings_path, QSettings::IniFormat);
    }

    const auto directory = QDir(application_directory).filePath("config");
    const auto path = QDir(directory).filePath("motion-bridge.ini");
    const auto legacy_portable_path = QDir(directory).filePath("companion.ini");
    QDir().mkpath(directory);
    if (!QFileInfo::exists(path)) {
        if (QFileInfo::exists(legacy_portable_path)) QFile::copy(legacy_portable_path, path);
        else if (QFileInfo::exists(legacy_path)) QFile::copy(legacy_path, path);
    }
    return QSettings(path, QSettings::IniFormat);
}
