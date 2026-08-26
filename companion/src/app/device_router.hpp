#pragma once

#include "fd_companion/types.hpp"

#include <QObject>
#include <QSerialPort>
#include <QUdpSocket>
#include <QWebSocket>

class DeviceRouter final : public QObject {
    Q_OBJECT

public:
    enum class Mode { None, Usb, Wifi, Intiface };
    Q_ENUM(Mode)

    explicit DeviceRouter(QObject* parent = nullptr);
    void set_mode(Mode mode);
    void set_usb_port(const QString& port);
    void set_wifi_endpoint(const QString& host, quint16 port);
    void set_intiface_url(const QUrl& url);
    void set_armed(bool armed);
    [[nodiscard]] Mode mode() const noexcept;
    [[nodiscard]] bool armed() const noexcept;
    void send(const fd::companion::Axes& axes);
    void emergency_stop();

signals:
    void status_changed(const QString& text, bool connected);

private slots:
    void on_intiface_message(const QString& message);
    void on_intiface_error(QAbstractSocket::SocketError error);

private:
    void ensure_transport();
    void send_tcode(const fd::companion::Axes& axes);
    void send_intiface_zero();

    Mode mode_{Mode::None};
    bool armed_{};
    QString usb_port_;
    QString wifi_host_{"tcode.local"};
    quint16 wifi_port_{8000};
    QUrl intiface_url_{"ws://127.0.0.1:12345"};
    QSerialPort* serial_{};
    QUdpSocket* udp_{};
    QWebSocket* intiface_{};
    int intiface_request_id_{1};
    int intiface_device_index_{-1};
};
