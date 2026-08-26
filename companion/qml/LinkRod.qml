import QtQuick
import QtQuick3D

Node {
    id: root
    required property vector3d startPoint
    required property vector3d endPoint
    property color rodColor: "#A9BAC7"
    property color bearingColor: "#C0C0C0"
    property real radius: 2.4
    property bool flat: false
    property real linkWidth: 10
    property real linkThickness: 5
    property real bearingRadius: 5.2

    readonly property vector3d delta: Qt.vector3d(endPoint.x - startPoint.x,
                                                  endPoint.y - startPoint.y,
                                                  endPoint.z - startPoint.z)
    readonly property real rodLength: Math.max(1, Math.sqrt(delta.x * delta.x
                                                            + delta.y * delta.y
                                                            + delta.z * delta.z))
    readonly property real horizontalLength: Math.sqrt(delta.y * delta.y + delta.z * delta.z)

    position: Qt.vector3d((startPoint.x + endPoint.x) * 0.5,
                          (startPoint.y + endPoint.y) * 0.5,
                          (startPoint.z + endPoint.z) * 0.5)
    eulerRotation: Qt.vector3d(Math.atan2(delta.z, delta.y) * 180 / Math.PI,
                               0,
                               -Math.atan2(delta.x, horizontalLength) * 180 / Math.PI)

    Model {
        source: root.flat ? "#Cube" : "#Cylinder"
        scale: root.flat
               ? Qt.vector3d(root.linkWidth / 100,
                             root.rodLength / 100,
                             root.linkThickness / 100)
               : Qt.vector3d(root.radius / 50,
                             root.rodLength / 100,
                             root.radius / 50)
        castsShadows: true
        receivesShadows: true
        materials: PrincipledMaterial {
            baseColor: root.rodColor
            metalness: 0.72
            roughness: 0.3
        }
    }

    Model {
        source: "#Sphere"
        y: -root.rodLength * 0.5
        scale: Qt.vector3d(root.bearingRadius / 50,
                          root.bearingRadius / 50,
                          root.bearingRadius / 50)
        materials: PrincipledMaterial {
            baseColor: root.bearingColor
            metalness: 0.85
            roughness: 0.26
        }
    }

    Model {
        source: "#Sphere"
        y: root.rodLength * 0.5
        scale: Qt.vector3d(root.bearingRadius / 50,
                          root.bearingRadius / 50,
                          root.bearingRadius / 50)
        materials: PrincipledMaterial {
            baseColor: root.bearingColor
            metalness: 0.85
            roughness: 0.26
        }
    }
}
