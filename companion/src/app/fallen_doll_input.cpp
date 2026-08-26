#include "fallen_doll_input.hpp"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>

using namespace fd::companion;

namespace {

std::optional<double> number(const QJsonValue& value) {
    return value.isDouble() ? std::optional<double>{value.toDouble()} : std::nullopt;
}

std::optional<Vec3> vec3(const QJsonValue& value) {
    const auto values = value.toArray();
    if (values.size() != 3) return std::nullopt;
    const auto x = number(values[0]); const auto y = number(values[1]); const auto z = number(values[2]);
    if (!x || !y || !z) return std::nullopt;
    return Vec3{*x, *y, *z};
}

std::optional<Quaternion> quaternion(const QJsonValue& value) {
    const auto values = value.toArray();
    if (values.size() != 4) return std::nullopt;
    const auto w = number(values[0]); const auto x = number(values[1]); const auto y = number(values[2]); const auto z = number(values[3]);
    if (!w || !x || !y || !z) return std::nullopt;
    return Quaternion{*w, *x, *y, *z};
}

} // namespace

FallenDollInput::FallenDollInput(QObject* parent) : QObject(parent) {
    watcher_ = new QFileSystemWatcher(this);
    stream_file_ = new QFile(this);
    poll_timer_ = new QTimer(this);
    poll_timer_->setInterval(20);
    coalesce_timer_ = new QTimer(this);
    coalesce_timer_->setSingleShot(true);
    coalesce_timer_->setInterval(1);
    connect(watcher_, &QFileSystemWatcher::fileChanged, this, &FallenDollInput::read_appended);
    connect(watcher_, &QFileSystemWatcher::directoryChanged, this, &FallenDollInput::read_appended);
    connect(poll_timer_, &QTimer::timeout, this, &FallenDollInput::read_appended);
    connect(coalesce_timer_, &QTimer::timeout, this, &FallenDollInput::emit_pending_frame);
}

void FallenDollInput::set_spool_path(const QString& path) {
    if (spool_path_ == path) return;
    if (!watcher_->files().isEmpty()) watcher_->removePaths(watcher_->files());
    if (!watcher_->directories().isEmpty()) watcher_->removePaths(watcher_->directories());
    spool_path_ = QDir::cleanPath(path);
    if (stream_file_->isOpen()) stream_file_->close();
    stream_file_->setFileName(spool_path_);
    offset_ = 0;
    partial_line_.clear();
    initial_sync_pending_ = true;
    connection_known_ = false;
    watch_current_path();
}

QString FallenDollInput::spool_path() const { return spool_path_; }

void FallenDollInput::start() {
    watch_current_path();
    if (initial_sync_pending_) {
        const QFileInfo info(spool_path_);
        if (info.exists()) {
            // An existing spool may contain many minutes of history. Real-time
            // startup begins at its current end; only newly appended frames are
            // useful and this prevents thousands of stale UI updates at launch.
            offset_ = info.size();
            partial_line_.clear();
            initial_sync_pending_ = false;
            publish_connection(true, tr("Fallen Doll stream connected"));
        }
    }
    read_appended();
    if (!poll_timer_->isActive()) poll_timer_->start();
}

void FallenDollInput::watch_current_path() {
    if (spool_path_.isEmpty()) return;
    const QFileInfo info(spool_path_);
    const auto directory = info.absolutePath();
    if (QFileInfo::exists(directory) && !watcher_->directories().contains(directory)) watcher_->addPath(directory);
    if (info.exists() && !watcher_->files().contains(spool_path_)) watcher_->addPath(spool_path_);
}

void FallenDollInput::read_appended() {
    watch_current_path();
    if (!QFileInfo::exists(spool_path_)) {
        if (stream_file_->isOpen()) stream_file_->close();
        publish_connection(false, tr("Waiting for Fallen Doll bone stream"));
        return;
    }
    if (!stream_file_->isOpen()) {
        stream_file_->setFileName(spool_path_);
        if (!stream_file_->open(QIODevice::ReadOnly)) {
            publish_connection(false, tr("Cannot read bone stream"));
            return;
        }
    }
    if (stream_file_->size() < offset_) {
        offset_ = 0;
        partial_line_.clear();
    }
    if (!stream_file_->seek(offset_)) return;
    partial_line_ += stream_file_->readAll();
    offset_ = stream_file_->pos();
    while (true) {
        const auto newline = partial_line_.indexOf('\n');
        if (newline < 0) break;
        const auto line = partial_line_.left(newline);
        partial_line_.remove(0, newline + 1);
        consume_line(line);
    }
    publish_connection(true, tr("Fallen Doll stream connected"));
}

void FallenDollInput::publish_connection(const bool connected, const QString& detail) {
    if (connection_known_ && connected_ == connected && connection_detail_ == detail) return;
    connection_known_ = true;
    connected_ = connected;
    connection_detail_ = detail;
    emit connection_changed(connected, detail);
}

void FallenDollInput::consume_line(const QByteArray& line) {
    const auto document = QJsonDocument::fromJson(line);
    if (!document.isObject()) return;
    const auto packet = document.object();
    if (packet.value("schema").toString() == u"motion-frame/v1") {
        consume_motion_frame(packet);
        return;
    }
    if (packet.value("type").toString() != u"skeleton_binary") return;
    const auto timestamp = packet.value("timestampMs").toVariant().toLongLong();
    if (timestamp <= 0) return;
    if (pending_timestamp_ >= 0 && pending_timestamp_ != timestamp) emit_pending_frame();
    if (pending_timestamp_ < 0) {
        pending_timestamp_ = timestamp;
        pending_frame_ = {};
        pending_frame_.game_id = "fallen-doll";
        pending_frame_.schema = "motion-frame/v1";
        pending_frame_.sequence = ++sequence_;
        pending_frame_.monotonic_time = std::chrono::milliseconds{timestamp};
        const auto trailer = packet.value("trailer").toObject();
        pending_frame_.action_active = trailer.value("hanimeActive").toBool();
        pending_frame_.action_id = trailer.value("hanimeId").toString().toStdString();
        pending_frame_.action_category = trailer.value("hanimeCategory").toString().toStdString();
    }
    Participant participant;
    participant.stable_key = packet.value("stableKey").toString().toStdString();
    participant.skeleton_id = packet.value("modelName").toString().toStdString();
    participant.role = packet.value("trailer").toObject().value("role").toString().toStdString();
    for (const auto& raw_bone : packet.value("bones").toArray()) {
        const auto object = raw_bone.toObject();
        const auto position = vec3(object.value("pos"));
        const auto rotation = quaternion(object.value("rot"));
        const auto name = object.value("name").toString();
        if (name.isEmpty() || !position || !rotation) continue;
        participant.bones.emplace(name.toStdString(), BonePose{name.toStdString(), *position, *rotation});
    }
    if (!participant.bones.empty()) pending_frame_.participants.push_back(std::move(participant));
    if (!coalesce_timer_->isActive()) coalesce_timer_->start();
}

void FallenDollInput::consume_motion_frame(const QJsonObject& packet) {
    // The public adapter protocol is deliberately accepted by the same spool
    // reader as Fallen Doll's compact stream. An external game only needs to
    // append one complete motion-frame/v1 JSON object per line; no DLL loading
    // or game-specific code is ever run inside Motion Bridge.
    emit_pending_frame();
    MotionFrame frame;
    frame.schema = "motion-frame/v1";
    frame.game_id = packet.value("gameId").toString().toStdString();
    frame.sequence = packet.value("sequence").toVariant().toULongLong();
    frame.monotonic_time = std::chrono::microseconds{packet.value("monotonicUs").toVariant().toLongLong()};
    const auto action = packet.value("action").toObject();
    frame.action_active = action.value("active").toBool();
    frame.action_id = action.value("id").toString().toStdString();
    frame.action_category = action.value("category").toString().toStdString();
    for (const auto& raw_participant : packet.value("participants").toArray()) {
        const auto raw = raw_participant.toObject();
        Participant participant;
        participant.stable_key = raw.value("stableKey").toString().toStdString();
        participant.role = raw.value("role").toString().toStdString();
        participant.skeleton_id = raw.value("skeletonId").toString().toStdString();
        for (const auto& raw_bone : raw.value("bones").toArray()) {
            const auto bone = raw_bone.toObject();
            const auto name = bone.value("name").toString();
            const auto position = vec3(bone.value("pos"));
            const auto rotation = quaternion(bone.value("rot"));
            if (name.isEmpty() || !position || !rotation) continue;
            participant.bones.emplace(name.toStdString(), BonePose{name.toStdString(), *position, *rotation});
        }
        if (!participant.bones.empty()) frame.participants.push_back(std::move(participant));
    }
    if (frame.game_id.empty() || frame.participants.empty()) return;
    if (frame.sequence == 0) frame.sequence = ++sequence_;
    emit frame_ready(std::move(frame));
}

void FallenDollInput::emit_pending_frame() {
    if (pending_timestamp_ < 0 || pending_frame_.participants.empty()) return;
    emit frame_ready(std::move(pending_frame_));
    pending_frame_ = {};
    pending_timestamp_ = -1;
}
