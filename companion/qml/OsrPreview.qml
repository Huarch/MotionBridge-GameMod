import QtQuick
import QtQuick.Controls
import QtQuick3D
import MotionBridge.Native

Rectangle {
    id: root

    required property real l0
    required property real l1
    required property real l2
    required property real r0
    required property real r1
    required property real r2
    property bool darkTheme: true
    // The device's visual front is the osr-emu front, not the cylinder axis.
    // This is a front view turned about 30 degrees into a readable oblique.
    // osr-emu uses a Z-up orbit camera. Keep the same convention here so the
    // device remains upright and the default composition matches its viewer.
    property real orbitYaw: 54.707947
    property real orbitPitch: 20.619009
    property real cameraDistance: 600.1625
    readonly property vector3d cameraTarget: Qt.vector3d(-62.330471, 28.868408, -17.219160)
    property vector3d orbitTarget: cameraTarget
    readonly property real orbitYawRadians: orbitYaw * Math.PI / 180
    readonly property real orbitPitchRadians: orbitPitch * Math.PI / 180

    // First-order receiver mapping around the neutral position reported by
    // osr-emu's SR6 firmware solver. The small arc terms preserve the visible
    // linkage shape near the ends of L0/L2 instead of drawing a Cartesian rig.
    readonly property real l0Centered: l0 - 0.5
    readonly property real l1Centered: l1 - 0.5
    readonly property real l2Centered: l2 - 0.5
    readonly property real carriageX: l2Centered * 59.66
    readonly property real carriageY: 212.398 - l1Centered * 41.883
                                             + Math.abs(l0Centered) * 4.775
                                             - Math.abs(l2Centered) * 5.524
    readonly property real carriageZ: -14.996 + l0Centered * 78.045
    readonly property color backgroundColor: darkTheme ? "#020407" : "#F4F8FB"
    readonly property color frameColor: darkTheme ? "#2E4658" : "#CAD9E3"
    readonly property color mutedColor: darkTheme ? "#91A8B8" : "#536D7D"
    readonly property color metalColor: darkTheme ? "#8297A6" : "#667F90"
    readonly property color baseColor: darkTheme ? "#243746" : "#AFC5D1"
    readonly property color accentColor: "#45C7E8"

    function resetCamera() {
        orbitTarget = cameraTarget
        orbitYaw = 54.707947
        orbitPitch = 20.619009
        cameraDistance = 600.1625
    }

    function setAxisView(yaw, pitch) {
        orbitYaw = yaw
        orbitPitch = pitch
        orbitTarget = cameraTarget
        cameraDistance = 560
    }

    function lookAtQuaternion(position, target) {
        let fx = target.x - position.x
        let fy = target.y - position.y
        let fz = target.z - position.z
        const fl = Math.sqrt(fx * fx + fy * fy + fz * fz)
        if (fl < 0.00001)
            return Qt.quaternion(1, 0, 0, 0)
        fx /= fl; fy /= fl; fz /= fl

        // right = normalize(forward × worldUp), worldUp = (0, 0, 1)
        let rx = fy
        let ry = -fx
        let rz = 0
        let rl = Math.sqrt(rx * rx + ry * ry)
        if (rl < 0.00001) {
            rx = 1; ry = 0; rz = 0; rl = 1
        }
        rx /= rl; ry /= rl; rz /= rl

        // up = right × forward
        const ux = ry * fz - rz * fy
        const uy = rz * fx - rx * fz
        const uz = rx * fy - ry * fx

        // Rotation matrix columns are local right, local up and local +Z.
        const m00 = rx,  m01 = ux,  m02 = -fx
        const m10 = ry,  m11 = uy,  m12 = -fy
        const m20 = rz,  m21 = uz,  m22 = -fz
        const trace = m00 + m11 + m22
        let qw, qx, qy, qz, s
        if (trace > 0) {
            s = Math.sqrt(trace + 1) * 2
            qw = 0.25 * s
            qx = (m21 - m12) / s
            qy = (m02 - m20) / s
            qz = (m10 - m01) / s
        } else if (m00 > m11 && m00 > m22) {
            s = Math.sqrt(1 + m00 - m11 - m22) * 2
            qw = (m21 - m12) / s
            qx = 0.25 * s
            qy = (m01 + m10) / s
            qz = (m02 + m20) / s
        } else if (m11 > m22) {
            s = Math.sqrt(1 + m11 - m00 - m22) * 2
            qw = (m02 - m20) / s
            qx = (m01 + m10) / s
            qy = 0.25 * s
            qz = (m12 + m21) / s
        } else {
            s = Math.sqrt(1 + m22 - m00 - m11) * 2
            qw = (m10 - m01) / s
            qx = (m02 + m20) / s
            qy = (m12 + m21) / s
            qz = 0.25 * s
        }
        const ql = Math.sqrt(qw * qw + qx * qx + qy * qy + qz * qz)
        return Qt.quaternion(qw / ql, qx / ql, qy / ql, qz / ql)
    }

    component ViewNavButton: Button {
        id: navButton
        required property string glyph
        property color accent: root.mutedColor
        width: 25
        height: 25
        text: glyph
        hoverEnabled: true
        background: Rectangle {
            radius: 8
            color: navButton.down ? root.accentColor
                                  : navButton.hovered ? root.frameColor
                                                      : "transparent"
            border.width: navButton.hovered ? 1 : 0
            border.color: root.darkTheme ? "#486477" : "#AFC2CE"
        }
        contentItem: Label {
            text: navButton.text
            color: navButton.down ? "#07141C" : navButton.accent
            font.pixelSize: 11
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }

    color: backgroundColor
    radius: 12
    border.color: frameColor
    clip: true

    View3D {
        id: viewport
        anchors.fill: parent
        anchors.margins: 1
        renderMode: View3D.Offscreen
        camera: camera

        environment: SceneEnvironment {
            backgroundMode: SceneEnvironment.Color
            clearColor: root.backgroundColor
            antialiasingMode: SceneEnvironment.MSAA
            antialiasingQuality: SceneEnvironment.High
            tonemapMode: SceneEnvironment.TonemapModeAces
        }

        Node {
            DirectionalLight {
                eulerRotation: Qt.vector3d(-38, 45, 0)
                brightness: 1.28
                color: "#FFFFFF"
                ambientColor: root.darkTheme ? "#A3AFBB" : "#D3DAE1"
                castsShadow: true
                shadowFactor: 12
                shadowMapQuality: Light.ShadowMapQualityMedium
            }

            DirectionalLight {
                eulerRotation: Qt.vector3d(24, -132, 0)
                brightness: 0.82
                color: root.darkTheme ? "#D5E2EA" : "#FFFFFF"
                ambientColor: root.darkTheme ? "#697784" : "#C5CED5"
                castsShadow: false
            }

            DirectionalLight {
                eulerRotation: Qt.vector3d(-52, 154, 0)
                brightness: 0.48
                color: root.darkTheme ? "#B8D6E5" : "#E3F3FA"
                ambientColor: "#000000"
                castsShadow: false
            }

            PerspectiveCamera {
                id: camera
                position: Qt.vector3d(
                              root.orbitTarget.x
                                  + root.cameraDistance * Math.cos(root.orbitPitchRadians)
                                    * Math.cos(root.orbitYawRadians),
                              root.orbitTarget.y
                                  + root.cameraDistance * Math.cos(root.orbitPitchRadians)
                                    * Math.sin(root.orbitYawRadians),
                              root.orbitTarget.z
                                  + root.cameraDistance * Math.sin(root.orbitPitchRadians))
                rotation: root.lookAtQuaternion(position, root.orbitTarget)
                clipNear: 5
                clipFar: 1500
                fieldOfView: 50

                DirectionalLight {
                    brightness: 0.72
                    color: root.darkTheme ? "#DCEAF3" : "#FFFFFF"
                    ambientColor: root.darkTheme ? "#687886" : "#C5D0D8"
                    castsShadow: false
                }
            }

            // The shell and arm geometry comes from the same MIT-licensed
            // osr-emu SR6 model used by F8Studio, rendered natively by Qt.
            Node {
                eulerRotation.x: -90

                ObjGeometry { id: baseGeometry; source: "qrc:/qt/qml/MotionBridge/App/assets/models/sr6/base.obj" }
                ObjGeometry { id: lidGeometry; source: "qrc:/qt/qml/MotionBridge/App/assets/models/sr6/lid.obj" }
                ObjGeometry { id: servoGeometry; source: "qrc:/qt/qml/MotionBridge/App/assets/models/sr6/main-arm-servos.obj" }
                ObjGeometry { id: armGeometry; source: "qrc:/qt/qml/MotionBridge/App/assets/models/sr6/arm.obj" }
                ObjGeometry { id: leftPitcherGeometry; source: "qrc:/qt/qml/MotionBridge/App/assets/models/sr6/left-pitcher.obj" }
                ObjGeometry { id: rightPitcherGeometry; source: "qrc:/qt/qml/MotionBridge/App/assets/models/sr6/right-pitcher.obj" }

                PrincipledMaterial {
                    id: shellMaterial
                    baseColor: root.darkTheme ? "#4A6190" : "#6682A6"
                    metalness: 0.18
                    roughness: 0.48
                }
                PrincipledMaterial {
                    id: darkMetalMaterial
                    baseColor: root.darkTheme ? "#292D33" : "#506370"
                    metalness: 0.2
                    roughness: 0.5
                }

                Model { geometry: baseGeometry; materials: darkMetalMaterial; castsShadows: true; receivesShadows: true }
                Model { geometry: lidGeometry; materials: shellMaterial; castsShadows: true; receivesShadows: true }
                Model { geometry: servoGeometry; materials: darkMetalMaterial; castsShadows: true }

                Model {
                    geometry: armGeometry
                    position: Qt.vector3d(58.5, 0, 49.92)
                    eulerRotation.y: 180
                    materials: shellMaterial
                    castsShadows: true
                }
                Model {
                    geometry: armGeometry
                    position: Qt.vector3d(-58.5, 0, 49.92)
                    materials: shellMaterial
                    castsShadows: true
                }
                Model {
                    geometry: armGeometry
                    position: Qt.vector3d(58.5, 30, 49.92)
                    eulerRotation: Qt.vector3d(180, 180, 0)
                    materials: shellMaterial
                    castsShadows: true
                }
                Model {
                    geometry: armGeometry
                    position: Qt.vector3d(-58.5, 30, 49.92)
                    eulerRotation.x: 180
                    materials: shellMaterial
                    castsShadows: true
                }
                Model {
                    geometry: leftPitcherGeometry
                    position: Qt.vector3d(14.318, -29.72, 49.325)
                    eulerRotation.x: -10.845
                    materials: shellMaterial
                    castsShadows: true
                }
                Model {
                    geometry: rightPitcherGeometry
                    position: Qt.vector3d(-14.318, -29.72, 49.325)
                    eulerRotation.x: -10.845
                    materials: shellMaterial
                    castsShadows: true
                }
            }

            LinkRod {
                startPoint: Qt.vector3d(-73, 49.92, 50)
                endPoint: Qt.vector3d(root.carriageX - 78.75, root.carriageY, root.carriageZ)
                rodColor: "#1E1E1E"
                flat: true
            }
            LinkRod {
                startPoint: Qt.vector3d(-73, 49.92, -80)
                endPoint: Qt.vector3d(root.carriageX - 72.75, root.carriageY, root.carriageZ)
                rodColor: "#1E1E1E"
                flat: true
            }
            LinkRod {
                startPoint: Qt.vector3d(73, 49.92, 50)
                endPoint: Qt.vector3d(root.carriageX + 78.75, root.carriageY, root.carriageZ)
                rodColor: "#1E1E1E"
                flat: true
            }
            LinkRod {
                startPoint: Qt.vector3d(73, 49.92, -80)
                endPoint: Qt.vector3d(root.carriageX + 72.75, root.carriageY, root.carriageZ)
                rodColor: "#1E1E1E"
                flat: true
            }
            LinkRod {
                startPoint: Qt.vector3d(-14.318, 63.44, 103.38)
                endPoint: Qt.vector3d(root.carriageX - 72.75, root.carriageY + 14.016, root.carriageZ + 53.18)
                rodColor: "#1E1E1E"
                flat: true
                linkWidth: 7
                linkThickness: 4
            }
            LinkRod {
                startPoint: Qt.vector3d(14.318, 63.44, 103.38)
                endPoint: Qt.vector3d(root.carriageX + 72.75, root.carriageY + 14.016, root.carriageZ + 53.18)
                rodColor: "#1E1E1E"
                flat: true
                linkWidth: 7
                linkThickness: 4
            }

            Node {
                id: carriage
                position: Qt.vector3d(root.carriageX, root.carriageY, root.carriageZ)
                eulerRotation: Qt.vector3d((root.r2 - 0.5) * 50,
                                           0,
                                           (0.5 - root.r1) * 30.24)

                Behavior on x { NumberAnimation { duration: 45; easing.type: Easing.OutCubic } }
                Behavior on y { NumberAnimation { duration: 45; easing.type: Easing.OutCubic } }
                Behavior on z { NumberAnimation { duration: 45; easing.type: Easing.OutCubic } }

                ObjGeometry {
                    id: receiverGeometry
                    source: "qrc:/qt/qml/MotionBridge/App/assets/models/sr6/receiver.obj"
                }

                Model {
                    geometry: receiverGeometry
                    eulerRotation.x: -90
                    castsShadows: true
                    receivesShadows: true
                    materials: PrincipledMaterial {
                        baseColor: root.darkTheme ? "#4A6190" : "#7895A5"
                        metalness: 0.18
                        roughness: 0.48
                    }
                }

                ObjGeometry {
                    id: caseGeometry
                    source: "qrc:/qt/qml/MotionBridge/App/assets/models/sr6/case.obj"
                }

                Node {
                    eulerRotation.z: (root.r0 - 0.5) * 240
                    Model {
                        geometry: caseGeometry
                        eulerRotation.x: -90
                        castsShadows: true
                        receivesShadows: true
                        materials: PrincipledMaterial {
                            baseColor: root.darkTheme ? "#30343A" : "#586773"
                            metalness: 0.18
                            roughness: 0.5
                        }
                    }
                }

            }
        }

    }

    // Keep input handling outside View3D. 2D pointer handlers embedded in a
    // View3D do not consistently own the complete preview surface on Windows.
    MouseArea {
        id: orbitInput
        z: 2
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        hoverEnabled: true
        preventStealing: true
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        property point previousPosition: Qt.point(0, 0)

        onPressed: mouse => {
            previousPosition = Qt.point(mouse.x, mouse.y)
            forceActiveFocus()
        }

        onPositionChanged: mouse => {
            if (mouse.buttons === Qt.NoButton)
                return

            const dx = mouse.x - previousPosition.x
            const dy = mouse.y - previousPosition.y
            previousPosition = Qt.point(mouse.x, mouse.y)

            const middlePans = (mouse.buttons & Qt.MiddleButton)
                               && (mouse.modifiers & Qt.ShiftModifier)
            const orbits = (mouse.buttons & Qt.LeftButton)
                           || ((mouse.buttons & Qt.MiddleButton) && !middlePans)
            const pans = (mouse.buttons & Qt.RightButton) || middlePans

            if (orbits) {
                root.orbitYaw += dx * 0.35
                root.orbitPitch = Math.max(-89,
                                           Math.min(89,
                                                    root.orbitPitch + dy * 0.35))

                if (Math.abs(root.orbitYaw) > 3600)
                    root.orbitYaw %= 360
            } else if (pans) {
                const factor = root.cameraDistance / Math.max(1, height)
                const right = camera.right
                const up = camera.up
                root.orbitTarget = root.orbitTarget
                    .minus(Qt.vector3d(right.x * dx * factor,
                                      right.y * dx * factor,
                                      right.z * dx * factor))
                    .plus(Qt.vector3d(up.x * dy * factor,
                                     up.y * dy * factor,
                                     up.z * dy * factor))
            }
        }

        onWheel: wheel => {
            const zoomFactor = Math.exp(-wheel.angleDelta.y * 0.001)
            root.cameraDistance = Math.max(220,
                                           Math.min(700,
                                                    root.cameraDistance * zoomFactor))
            wheel.accepted = true
        }

        onDoubleClicked: mouse => {
            if (mouse.button === Qt.LeftButton)
                root.resetCamera()
        }
    }

    Row {
        z: 3
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.margins: 12
        spacing: 8

        Rectangle {
            width: 7
            height: 7
            radius: 4
            anchors.verticalCenter: parent.verticalCenter
            color: root.accentColor
        }
        Label {
            text: qsTr("LIVE SR6 / OSR PREVIEW")
            color: root.mutedColor
            font.pixelSize: 12
            font.bold: true
        }
    }

    Rectangle {
        z: 4
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 10
        width: 98
        height: 66
        radius: 12
        color: root.darkTheme ? "#D9111824" : "#EFFFFFFF"
        border.color: root.frameColor

        Column {
            anchors.centerIn: parent
            spacing: 4

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 5
                ViewNavButton {
                    glyph: "↶"
                    onClicked: root.orbitYaw -= 30
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("Rotate view left 30°")
                }
                ViewNavButton {
                    glyph: "◆"
                    accent: root.accentColor
                    onClicked: root.resetCamera()
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("Reset oblique view")
                }
                ViewNavButton {
                    glyph: "↷"
                    onClicked: root.orbitYaw += 30
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("Rotate view right 30°")
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 5
                ViewNavButton {
                    glyph: "X"
                    accent: "#E97070"
                    onClicked: root.setAxisView(0, 0)
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("Right view")
                }
                ViewNavButton {
                    glyph: "Y"
                    accent: "#70D59A"
                    onClicked: root.setAxisView(90, 0)
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("Front view")
                }
                ViewNavButton {
                    glyph: "Z"
                    accent: "#6CA9F4"
                    onClicked: root.setAxisView(root.orbitYaw, 89)
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("Top view")
                }
            }
        }
    }

    Label {
        z: 3
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 12
        text: qsTr("Left/MMB orbit · Shift+MMB/right pan · Wheel zoom · Double-click reset")
        color: root.mutedColor
        font.pixelSize: 9
        opacity: 0.72
    }
}
