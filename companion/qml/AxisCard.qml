import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root
    required property int axisIndex
    required property string axisName
    required property real axisValue
    property bool darkTheme: true
    property real gain: 1.0
    property real outputMinimum: 0.0
    property real outputMaximum: 1.0
    Layout.fillWidth: true
    Layout.preferredHeight: 164
    radius: 15
    color: darkTheme ? "#111722" : "#FFFFFF"
    border.color: darkTheme ? "#202B3B" : "#D5DEE9"

    readonly property color accent: axisIndex === 0 ? "#59D7FF" : axisIndex < 3 ? "#7C91FF" : "#B27DFF"
    readonly property color primaryText: darkTheme ? "#F1F5FB" : "#182334"
    readonly property color secondaryText: darkTheme ? "#AAB7C9" : "#536276"
    readonly property color mutedText: darkTheme ? "#637189" : "#7A889A"
    readonly property color trackSurface: darkTheme ? "#080D15" : "#E8EDF3"
    readonly property color valueSurface: darkTheme ? "#192231" : "#EEF2F7"

    function commitGain() {
        companion.set_axis_gain(root.axisIndex, gainSlider.value)
    }

    function commitRange() {
        companion.set_axis_range(root.axisIndex,
                                 rangeSlider.first.value,
                                 rangeSlider.second.value)
    }

    Timer {
        interval: 40
        repeat: true
        running: gainSlider.pressed
        onTriggered: root.commitGain()
    }

    Timer {
        interval: 40
        repeat: true
        running: rangeSlider.first.pressed || rangeSlider.second.pressed
        onTriggered: root.commitRange()
    }

    ColumnLayout {
        anchors.fill: parent; anchors.margins: 15; spacing: 8
        RowLayout {
            Layout.fillWidth: true
            Rectangle { width: 8; height: 8; radius: 4; color: root.accent }
            Label { text: root.axisName; color: root.secondaryText; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 0.7 }
            Item { Layout.fillWidth: true }
            Label { text: Math.round(root.axisValue * 9999).toString().padStart(4, "0"); color: root.primaryText; font.family: "Cascadia Mono"; font.pixelSize: 17; font.weight: Font.DemiBold }
        }
        Rectangle {
            Layout.fillWidth: true; Layout.preferredHeight: 8; radius: 4; color: root.trackSurface
            Rectangle {
                width: Math.max(8, parent.width * Math.max(0, Math.min(1, root.axisValue))); height: parent.height; radius: 4
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: Qt.darker(root.accent, 1.35) }
                    GradientStop { position: 1; color: root.accent }
                }
                Behavior on width { NumberAnimation { duration: 42; easing.type: Easing.OutQuad } }
            }
            Rectangle { width: 1; height: 14; y: -3; x: parent.width / 2; color: root.darkTheme ? "#718097" : "#6D7D91"; opacity: 0.55 }
        }
        RowLayout {
            Layout.fillWidth: true
            Label { text: qsTr("GAIN"); color: root.mutedText; font.pixelSize: 9; font.bold: true; font.letterSpacing: 0.8 }
            Slider {
                id: gainSlider
                Layout.fillWidth: true; from: 0.25; to: 4.0; stepSize: 0.05; value: root.gain
                onPressedChanged: if (!pressed) root.commitGain()
            }
            Rectangle { width: 48; height: 24; radius: 8; color: root.valueSurface
                Label { anchors.centerIn: parent; text: gainSlider.value.toFixed(2) + "×"; color: root.secondaryText; font.pixelSize: 10; font.family: "Cascadia Mono" }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            Label { text: qsTr("RANGE"); color: root.mutedText; font.pixelSize: 9; font.bold: true; font.letterSpacing: 0.8 }
            RangeSlider {
                id: rangeSlider
                Layout.fillWidth: true
                from: 0.0
                to: 1.0
                stepSize: 0.01
                first.value: root.outputMinimum
                second.value: root.outputMaximum
                first.onPressedChanged: if (!first.pressed) root.commitRange()
                second.onPressedChanged: if (!second.pressed) root.commitRange()

                background: Rectangle {
                    x: rangeSlider.leftPadding
                    y: rangeSlider.topPadding + rangeSlider.availableHeight / 2 - height / 2
                    width: rangeSlider.availableWidth
                    height: 6
                    radius: 3
                    color: root.trackSurface
                    Rectangle {
                        x: rangeSlider.first.visualPosition * parent.width
                        width: (rangeSlider.second.visualPosition - rangeSlider.first.visualPosition) * parent.width
                        height: parent.height
                        radius: 3
                        color: root.accent
                        opacity: 0.82
                    }
                }
                first.handle: Rectangle {
                    x: rangeSlider.leftPadding + rangeSlider.first.visualPosition * (rangeSlider.availableWidth - width)
                    y: rangeSlider.topPadding + rangeSlider.availableHeight / 2 - height / 2
                    width: 16; height: 16; radius: 8
                    color: rangeSlider.first.pressed ? root.accent : root.primaryText
                    border.width: 2; border.color: root.accent
                }
                second.handle: Rectangle {
                    x: rangeSlider.leftPadding + rangeSlider.second.visualPosition * (rangeSlider.availableWidth - width)
                    y: rangeSlider.topPadding + rangeSlider.availableHeight / 2 - height / 2
                    width: 16; height: 16; radius: 8
                    color: rangeSlider.second.pressed ? root.accent : root.primaryText
                    border.width: 2; border.color: root.accent
                }
            }
            Rectangle { width: 88; height: 24; radius: 8; color: root.valueSurface
                Label {
                    anchors.centerIn: parent
                    text: Math.round(rangeSlider.first.value * 9999).toString().padStart(4, "0")
                          + "–"
                          + Math.round(rangeSlider.second.value * 9999).toString().padStart(4, "0")
                    color: root.secondaryText
                    font.pixelSize: 9
                    font.family: "Cascadia Mono"
                }
            }
        }
    }
}
