#pragma once

#include "realtime_pipeline.hpp"

#include <QObject>
#include <QThread>
#include <QTimer>
#include <QStringList>
#include <QVariantList>

class CompanionController final : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString streamStatus READ stream_status NOTIFY statusChanged)
    Q_PROPERTY(bool streamConnected READ stream_connected NOTIFY statusChanged)
    Q_PROPERTY(QString outputStatus READ output_status NOTIFY statusChanged)
    Q_PROPERTY(QString motionState READ motion_state NOTIFY snapshotChanged)
    Q_PROPERTY(QString actionName READ action_name NOTIFY snapshotChanged)
    Q_PROPERTY(QVariantList rawAxes READ raw_axes NOTIFY snapshotChanged)
    Q_PROPERTY(QVariantList deviceAxes READ device_axes NOTIFY snapshotChanged)
    Q_PROPERTY(bool armed READ armed NOTIFY statusChanged)
    Q_PROPERTY(QString outputMode READ output_mode NOTIFY statusChanged)
    Q_PROPERTY(QString spoolPath READ spool_path NOTIFY statusChanged)
    Q_PROPERTY(QString usbPort READ usb_port NOTIFY settingsChanged)
    Q_PROPERTY(QString wifiHost READ wifi_host NOTIFY settingsChanged)
    Q_PROPERTY(int wifiPort READ wifi_port NOTIFY settingsChanged)
    Q_PROPERTY(QString intifaceUrl READ intiface_url NOTIFY settingsChanged)
    Q_PROPERTY(QVariantList axisGains READ axis_gains NOTIFY settingsChanged)
    Q_PROPERTY(QVariantList axisMinimums READ axis_minimums NOTIFY settingsChanged)
    Q_PROPERTY(QVariantList axisMaximums READ axis_maximums NOTIFY settingsChanged)
    Q_PROPERTY(QStringList usbPorts READ usb_ports NOTIFY usbPortsChanged)
    Q_PROPERTY(QString theme READ theme NOTIFY themeChanged)

public:
    explicit CompanionController(QObject* parent = nullptr);
    ~CompanionController() override;

    [[nodiscard]] QString stream_status() const;
    [[nodiscard]] bool stream_connected() const;
    [[nodiscard]] QString output_status() const;
    [[nodiscard]] QString motion_state() const;
    [[nodiscard]] QString action_name() const;
    [[nodiscard]] QVariantList raw_axes() const;
    [[nodiscard]] QVariantList device_axes() const;
    [[nodiscard]] bool armed() const;
    [[nodiscard]] QString output_mode() const;
    [[nodiscard]] QString spool_path() const;
    [[nodiscard]] QString usb_port() const;
    [[nodiscard]] QString wifi_host() const;
    [[nodiscard]] int wifi_port() const;
    [[nodiscard]] QString intiface_url() const;
    [[nodiscard]] QVariantList axis_gains() const;
    [[nodiscard]] QVariantList axis_minimums() const;
    [[nodiscard]] QVariantList axis_maximums() const;
    [[nodiscard]] QStringList usb_ports() const;
    [[nodiscard]] QString theme() const;

    Q_INVOKABLE void set_armed(bool armed);
    Q_INVOKABLE void emergency_stop();
    Q_INVOKABLE void set_output_mode(const QString& mode);
    Q_INVOKABLE void set_usb_port(const QString& port);
    Q_INVOKABLE void set_wifi_endpoint(const QString& host, int port);
    Q_INVOKABLE void set_intiface_url(const QString& url);
    Q_INVOKABLE void set_axis_gain(int axis, double value);
    Q_INVOKABLE void set_axis_range(int axis, double minimum, double maximum);
    Q_INVOKABLE void set_stream_path(const QString& path);
    Q_INVOKABLE void refresh_usb_ports();
    Q_INVOKABLE void set_theme(const QString& theme);

signals:
    void snapshotChanged();
    void statusChanged();
    void settingsChanged();
    void usbPortsChanged();
    void themeChanged();

private:
    QThread realtime_thread_;
    RealtimePipeline* pipeline_{};
    QString stream_status_{tr("Starting real-time pipeline")};
    bool stream_connected_{};
    QString output_status_{tr("Output disarmed")};
    QString motion_state_{"idle"};
    QString action_name_;
    QVariantList raw_axes_{0.5, 0.5, 0.5, 0.5, 0.5, 0.5};
    QVariantList device_axes_{0.5, 0.5, 0.5, 0.5, 0.5, 0.5};
    QString output_mode_{"none"};
    QString spool_path_;
    bool armed_{};
    QString usb_port_;
    QString wifi_host_{"tcode.local"};
    int wifi_port_{8000};
    QString intiface_url_{"ws://127.0.0.1:12345"};
    QVariantList axis_gains_{1.0, 1.0, 1.0, 1.0, 1.0, 1.0};
    QVariantList axis_minimums_{0.0, 0.0, 0.0, 0.0, 0.0, 0.0};
    QVariantList axis_maximums_{1.0, 1.0, 1.0, 1.0, 1.0, 1.0};
    QStringList usb_ports_;
    QTimer usb_scan_timer_;
    QString theme_{"dark"};
};
