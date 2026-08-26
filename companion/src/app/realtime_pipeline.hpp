#pragma once

#include "device_router.hpp"
#include "fallen_doll_input.hpp"
#include "fd_companion/motion_engine.hpp"

#include <QElapsedTimer>
#include <QObject>
#include <QTimer>
#include <QVariantList>

#include <optional>

class RealtimePipeline final : public QObject {
    Q_OBJECT

public:
    explicit RealtimePipeline(QObject* parent = nullptr);

public slots:
    void start();
    void stop();
    void set_armed(bool armed);
    void emergency_stop();
    void set_output_mode(const QString& mode);
    void set_usb_port(const QString& port);
    void set_wifi_endpoint(const QString& host, int port);
    void set_intiface_url(const QString& url);
    void set_axis_gain(int axis, double value);
    void set_axis_range(int axis, double minimum, double maximum);
    void set_stream_path(const QString& path);
    void set_theme(const QString& theme);

signals:
    void snapshot_ready(const QString& state, const QString& action, const QVariantList& raw, const QVariantList& device);
    void stream_status_changed(bool connected, const QString& text);
    void output_status_changed(const QString& text, bool armed, const QString& mode);
    void spool_path_changed(const QString& path);
    void connection_settings_changed(const QString& usb_port, const QString& wifi_host, int wifi_port, const QString& intiface_url);
    void axis_gains_changed(const QVariantList& gains);
    void axis_ranges_changed(const QVariantList& minimums, const QVariantList& maximums);
    void theme_changed(const QString& theme);

private slots:
    void on_frame(fd::companion::MotionFrame frame);
    void on_heartbeat();

private:
    void load_settings();
    void save_settings();
    void publish_snapshot();
    void publish_connection_settings();
    void publish_axis_gains();
    void publish_axis_ranges();
    [[nodiscard]] std::chrono::microseconds now() const;

    fd::companion::MotionEngine engine_;
    FallenDollInput* input_{};
    DeviceRouter* device_{};
    QElapsedTimer clock_;
    QTimer* heartbeat_{};
    fd::companion::EngineSnapshot snapshot_;
    std::optional<fd::companion::EngineSnapshot> last_ui_snapshot_;
    std::chrono::microseconds last_input_time_{};
    QString spool_path_;
    QString usb_port_;
    QString wifi_host_{"tcode.local"};
    int wifi_port_{8000};
    QString intiface_url_{"ws://127.0.0.1:12345"};
    QString theme_{"dark"};
};
