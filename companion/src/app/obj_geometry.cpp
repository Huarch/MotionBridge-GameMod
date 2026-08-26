#include "obj_geometry.hpp"

#include <QFile>
#include <QVector2D>
#include <QVector3D>

#include <algorithm>
#include <limits>

namespace {
struct Vertex {
    QVector3D position;
    QVector3D normal;
};

struct FaceIndex {
    int position{-1};
    int normal{-1};
};

int resolve_index(const QByteArray& value, int count) {
    bool ok = false;
    const int parsed = value.toInt(&ok);
    if (!ok || parsed == 0) return -1;
    return parsed > 0 ? parsed - 1 : count + parsed;
}

FaceIndex parse_face_index(const QByteArray& token, int position_count, int normal_count) {
    const QList<QByteArray> fields = token.split('/');
    FaceIndex result;
    if (!fields.isEmpty()) result.position = resolve_index(fields[0], position_count);
    if (fields.size() >= 3 && !fields[2].isEmpty()) result.normal = resolve_index(fields[2], normal_count);
    return result;
}
}

ObjGeometry::ObjGeometry(QQuick3DObject* parent) : QQuick3DGeometry(parent) {}

QUrl ObjGeometry::source() const { return source_; }

void ObjGeometry::setSource(const QUrl& source) {
    if (source_ == source) return;
    source_ = source;
    rebuild();
    emit sourceChanged();
}

void ObjGeometry::rebuild() {
    clear();
    if (source_.isEmpty()) return;

    const QString path = source_.scheme() == QStringLiteral("qrc")
        ? QStringLiteral(":") + source_.path()
        : source_.toLocalFile();
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        qWarning("Could not open OBJ geometry: %s", qPrintable(path));
        return;
    }

    QVector<QVector3D> positions;
    QVector<QVector3D> normals;
    QVector<Vertex> vertices;
    QVector3D minimum(std::numeric_limits<float>::max(),
                      std::numeric_limits<float>::max(),
                      std::numeric_limits<float>::max());
    QVector3D maximum(std::numeric_limits<float>::lowest(),
                      std::numeric_limits<float>::lowest(),
                      std::numeric_limits<float>::lowest());

    while (!file.atEnd()) {
        const QByteArray line = file.readLine().trimmed();
        if (line.startsWith("v ")) {
            const QList<QByteArray> fields = line.simplified().split(' ');
            if (fields.size() >= 4) {
                positions.append(QVector3D(fields[1].toFloat(), fields[2].toFloat(), fields[3].toFloat()));
            }
        } else if (line.startsWith("vn ")) {
            const QList<QByteArray> fields = line.simplified().split(' ');
            if (fields.size() >= 4) {
                normals.append(QVector3D(fields[1].toFloat(), fields[2].toFloat(), fields[3].toFloat()).normalized());
            }
        } else if (line.startsWith("f ")) {
            const QList<QByteArray> fields = line.simplified().split(' ');
            if (fields.size() < 4) continue;

            QVector<FaceIndex> face;
            face.reserve(fields.size() - 1);
            for (qsizetype i = 1; i < fields.size(); ++i) {
                face.append(parse_face_index(fields[i], positions.size(), normals.size()));
            }

            for (qsizetype i = 1; i + 1 < face.size(); ++i) {
                const FaceIndex triangle[3] = {face[0], face[i], face[i + 1]};
                if (std::ranges::any_of(triangle, [&](const FaceIndex& item) {
                        return item.position < 0 || item.position >= positions.size();
                    })) {
                    continue;
                }

                const QVector3D face_normal = QVector3D::crossProduct(
                    positions[triangle[1].position] - positions[triangle[0].position],
                    positions[triangle[2].position] - positions[triangle[0].position]).normalized();
                for (const FaceIndex& item : triangle) {
                    const QVector3D position = positions[item.position];
                    const QVector3D normal = item.normal >= 0 && item.normal < normals.size()
                        ? normals[item.normal]
                        : face_normal;
                    vertices.append(Vertex{position, normal});
                    minimum.setX(std::min(minimum.x(), position.x()));
                    minimum.setY(std::min(minimum.y(), position.y()));
                    minimum.setZ(std::min(minimum.z(), position.z()));
                    maximum.setX(std::max(maximum.x(), position.x()));
                    maximum.setY(std::max(maximum.y(), position.y()));
                    maximum.setZ(std::max(maximum.z(), position.z()));
                }
            }
        }
    }

    if (vertices.isEmpty()) return;
    setStride(sizeof(Vertex));
    setVertexData(QByteArray(reinterpret_cast<const char*>(vertices.constData()),
                             vertices.size() * static_cast<qsizetype>(sizeof(Vertex))));
    addAttribute(Attribute::PositionSemantic, offsetof(Vertex, position), Attribute::F32Type);
    addAttribute(Attribute::NormalSemantic, offsetof(Vertex, normal), Attribute::F32Type);
    setBounds(minimum, maximum);
    update();
}
