#include "companion_controller.hpp"
#include "language_controller.hpp"
#include "obj_geometry.hpp"

#include <QGuiApplication>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <qqml.h>

namespace {
void startup_message_handler(QtMsgType, const QMessageLogContext&, const QString& message) {
    QFile log(QDir(QDir::tempPath()).filePath("MotionBridge-startup.log"));
    if (!log.open(QIODevice::WriteOnly | QIODevice::Append | QIODevice::Text)) return;
    log.write(QDateTime::currentDateTime().toString(Qt::ISODate).toUtf8());
    log.write(" ");
    log.write(message.toUtf8());
    log.write("\n");
}
}

int main(int argc, char* argv[]) {
    qInstallMessageHandler(startup_message_handler);
    qputenv("QT_QUICK_CONTROLS_STYLE", "Basic");
    QGuiApplication app(argc, argv);
    QCoreApplication::setOrganizationName("Motion Bridge");
    QCoreApplication::setApplicationName("Motion Bridge");
    QCoreApplication::setOrganizationDomain("motionbridge.local");
    app.setWindowIcon(QIcon(QStringLiteral(
        ":/qt/qml/MotionBridge/App/assets/icons/motion-bridge.svg")));

    LanguageController language_controller(&app);
    CompanionController controller;
    qmlRegisterType<ObjGeometry>("MotionBridge.Native", 1, 0, "ObjGeometry");
    QQmlApplicationEngine engine;
    language_controller.set_engine(&engine);
    engine.rootContext()->setContextProperty("companion", &controller);
    engine.rootContext()->setContextProperty("languageController", &language_controller);
    const QUrl url(QStringLiteral("qrc:/qt/qml/MotionBridge/App/qml/Main.qml"));
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed, &app, [] { QCoreApplication::exit(-1); }, Qt::QueuedConnection);
    engine.load(url);
    return app.exec();
}
