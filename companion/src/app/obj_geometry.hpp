#pragma once

#include <QQuick3DGeometry>
#include <QUrl>

class ObjGeometry : public QQuick3DGeometry {
    Q_OBJECT
    Q_PROPERTY(QUrl source READ source WRITE setSource NOTIFY sourceChanged)

public:
    explicit ObjGeometry(QQuick3DObject* parent = nullptr);

    [[nodiscard]] QUrl source() const;
    void setSource(const QUrl& source);

signals:
    void sourceChanged();

private:
    void rebuild();

    QUrl source_;
};
