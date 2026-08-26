#pragma once

#include "fd_companion/types.hpp"

#include <QFileSystemWatcher>
#include <QFile>
#include <QObject>
#include <QTimer>

class FallenDollInput final : public QObject {
    Q_OBJECT

public:
    explicit FallenDollInput(QObject* parent = nullptr);

    void set_spool_path(const QString& path);
    [[nodiscard]] QString spool_path() const;
    void start();

signals:
    void frame_ready(fd::companion::MotionFrame frame);
    void connection_changed(bool connected, const QString& detail);

private slots:
    void read_appended();
    void emit_pending_frame();

private:
    void watch_current_path();
    void consume_line(const QByteArray& line);
    void consume_motion_frame(const QJsonObject& packet);
    void publish_connection(bool connected, const QString& detail);

    QFileSystemWatcher* watcher_{};
    QFile* stream_file_{};
    // QFileSystemWatcher is a prompt wake-up hint. The low-cost polling timer is
    // the reliable path because UE4SS can keep an append-only file open and some
    // Windows file-system notifications are coalesced during scene transitions.
    QTimer* poll_timer_{};
    QTimer* coalesce_timer_{};
    QString spool_path_;
    qint64 offset_{};
    QByteArray partial_line_;
    bool initial_sync_pending_{true};
    bool connection_known_{};
    bool connected_{};
    QString connection_detail_;
    qint64 pending_timestamp_{-1};
    fd::companion::MotionFrame pending_frame_;
    quint64 sequence_{};
};
