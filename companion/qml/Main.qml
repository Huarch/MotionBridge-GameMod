import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

ApplicationWindow {
    id: window
    width: 860
    height: 190
    minimumWidth: 800
    minimumHeight: 186
    visible: true
    flags: Qt.Window | Qt.FramelessWindowHint
    color: "transparent"
    title: qsTr("Motion Bridge")
    font.family: "Segoe UI Variable"

    property bool connectionExpanded: false
    property bool tuningExpanded: false
    readonly property bool darkTheme: companion.theme !== "light"
    readonly property bool expanded: connectionExpanded || tuningExpanded
    readonly property color surface: darkTheme ? "#0C111A" : "#F3F6FA"
    readonly property color titleSurface: darkTheme ? "#0A0F17" : "#FFFFFF"
    readonly property color headerSurface: darkTheme ? "#0D131D" : "#F8FAFD"
    readonly property color footerSurface: darkTheme ? "#0A1018" : "#EEF3F8"
    readonly property color panel: darkTheme ? "#111824" : "#FFFFFF"
    readonly property color panelAlt: darkTheme ? "#121A26" : "#F7F9FC"
    readonly property color fieldSurface: darkTheme ? "#0C121B" : "#F2F5F9"
    readonly property color hoverSurface: darkTheme ? "#1B2635" : "#E8EEF5"
    readonly property color activeSurface: darkTheme ? "#18243A" : "#E5EBFF"
    readonly property color outline: darkTheme ? "#202B3B" : "#D5DEE9"
    readonly property color textPrimary: darkTheme ? "#EAF0F8" : "#182334"
    readonly property color textSecondary: darkTheme ? "#98A6B9" : "#536276"
    readonly property color textMuted: darkTheme ? "#637189" : "#7A889A"
    readonly property color primary: "#667DFF"
    readonly property color cyan: "#61DFFF"

    function resizeForContent() {
        if (visibility === Window.Maximized) return
        const oldCenterX = x + width / 2
        const oldCenterY = y + height / 2
        const targetWidth = tuningExpanded ? 1160
                          : connectionExpanded ? 960
                          : 860
        // These workspaces have fixed layouts. Using their asynchronous
        // implicitHeight here can capture an intermediate value immediately
        // after visibility changes and leave the panel clipped. Keep explicit
        // complete heights in sync with the layouts below.
        const targetHeight = connectionExpanded && tuningExpanded ? 890
                           : connectionExpanded ? 490
                           : tuningExpanded ? 620
                           : 190
        minimumWidth = tuningExpanded ? 980
                     : connectionExpanded ? 860
                     : 800
        minimumHeight = expanded ? targetHeight : 186
        width = targetWidth
        height = targetHeight
        // Preserve the window centre while switching between compact and
        // expanded modes. QML's QScreen geometry is not consistently exposed
        // on every Windows/Qt backend, so native dragging remains the final
        // authority for multi-monitor placement.
        x = oldCenterX - width / 2
        y = oldCenterY - height / 2
    }

    function toggleConnection() {
        if (!connectionExpanded) companion.refresh_usb_ports()
        connectionExpanded = !connectionExpanded
        Qt.callLater(resizeForContent)
    }

    function togglePreview() {
        if (previewWindow.visible) {
            previewWindow.hide()
        } else {
            previewWindow.show()
            previewWindow.raise()
            previewWindow.requestActivate()
        }
    }

    function toggleTuning() {
        tuningExpanded = !tuningExpanded
        Qt.callLater(resizeForContent)
    }

    function motionStateLabel(state) {
        switch (state) {
        case "active": return qsTr("ACTIVE")
        case "acquiring": return qsTr("ACQUIRING")
        case "releasing": return qsTr("RELEASING")
        case "unmapped": return qsTr("UNMAPPED")
        case "fault": return qsTr("FAULT")
        default: return qsTr("IDLE")
        }
    }

    component WindowButton: Button {
        id: control
        required property string glyph
        property color hoverColor: window.hoverSurface
        property real glyphSize: 13
        width: 42; height: 36
        text: glyph
        hoverEnabled: true
        background: Rectangle {
            radius: 8
            color: control.hovered ? control.hoverColor : "transparent"
            border.width: 0
        }
        contentItem: Label {
            text: control.text
            color: control.hovered && control.hoverColor === "#B84350" ? "white" : window.textSecondary
            font.pixelSize: control.glyphSize
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }

    component LanguageOption: MenuItem {
        id: languageOption
        required property string languageCode
        required property string optionText
        implicitWidth: 154
        implicitHeight: 38
        text: optionText
        checkable: true
        checked: languageController.language === languageCode
        hoverEnabled: true
        leftPadding: 9
        rightPadding: 9
        onTriggered: languageController.set_language(languageCode)

        indicator: Item { implicitWidth: 0; implicitHeight: 0 }
        arrow: Item { implicitWidth: 0; implicitHeight: 0 }

        background: Rectangle {
            radius: 8
            color: languageOption.highlighted || languageOption.hovered
                   ? window.hoverSurface : "transparent"
            border.width: languageOption.checked ? 1 : 0
            border.color: languageOption.checked
                          ? (window.darkTheme ? "#5268C7" : "#AEBBEE")
                          : "transparent"
        }

        contentItem: RowLayout {
            spacing: 9

            Rectangle {
                Layout.preferredWidth: 18
                Layout.preferredHeight: 18
                radius: 6
                color: languageOption.checked ? window.primary : "transparent"
                border.width: languageOption.checked ? 0 : 1
                border.color: window.outline

                Label {
                    anchors.centerIn: parent
                    text: "✓"
                    visible: languageOption.checked
                    color: "white"
                    font.pixelSize: 11
                    font.bold: true
                }
            }

            Label {
                Layout.fillWidth: true
                text: languageOption.optionText
                color: languageOption.checked ? window.textPrimary : window.textSecondary
                font.pixelSize: 11
                font.weight: languageOption.checked ? Font.DemiBold : Font.Normal
                verticalAlignment: Text.AlignVCenter
            }
        }
    }

    component StatusChip: Rectangle {
        required property string caption
        required property string value
        property color accent: window.cyan
        Layout.preferredWidth: 104
        Layout.minimumWidth: 92
        Layout.preferredHeight: 42
        radius: 12
        color: window.panelAlt
        border.color: window.outline
        RowLayout {
            anchors.fill: parent; anchors.leftMargin: 11; anchors.rightMargin: 10; spacing: 8
            Rectangle { width: 6; height: 6; radius: 3; color: parent.parent.accent }
            ColumnLayout {
                Layout.fillWidth: true; spacing: 1
                Label { text: parent.parent.parent.caption; color: window.textMuted; font.pixelSize: 8; font.weight: Font.DemiBold; font.letterSpacing: 0.7 }
                Label { Layout.fillWidth: true; text: parent.parent.parent.value; color: window.textPrimary; elide: Text.ElideRight; font.pixelSize: 10; font.weight: Font.DemiBold }
            }
        }
    }

    component DisclosureButton: Button {
        required property string label
        required property string detail
        required property bool opened
        Layout.fillWidth: true
        Layout.preferredHeight: 40
        leftPadding: 14
        rightPadding: 8
        background: Rectangle {
            radius: 12
            color: parent.opened ? window.activeSurface : parent.hovered ? window.hoverSurface : "transparent"
            border.width: parent.opened ? 1 : 0
            border.color: parent.opened ? (window.darkTheme ? "#536CCB" : "#8799E8") : "transparent"
        }
        contentItem: RowLayout {
            spacing: 8
            Label { text: parent.parent.label; color: window.textPrimary; font.pixelSize: 11; font.weight: Font.DemiBold }
            Label { text: parent.parent.detail; color: window.textMuted; font.pixelSize: 10 }
            Item { Layout.fillWidth: true }
            Rectangle {
                Layout.preferredWidth: 26
                Layout.preferredHeight: 26
                radius: 8
                color: parent.parent.opened ? (window.darkTheme ? "#283865" : "#DDE4FF") : window.panelAlt
                border.color: window.outline
                Item {
                    anchors.centerIn: parent
                    width: 12
                    height: 8
                    property color strokeColor: parent.parent.parent.opened ? "#8FA3FF" : window.textSecondary
                    rotation: parent.parent.parent.opened ? 180 : 0
                    Behavior on rotation { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    Rectangle {
                        width: 7; height: 1.5; radius: 0.75
                        x: -0.2; y: 2.5
                        color: parent.strokeColor
                        rotation: 42
                    }
                    Rectangle {
                        width: 7; height: 1.5; radius: 0.75
                        x: 5.2; y: 2.5
                        color: parent.strokeColor
                        rotation: -42
                    }
                }
            }
        }
    }

    component ViewerButton: Button {
        required property string label
        required property string detail
        required property bool opened
        Layout.fillWidth: true
        Layout.preferredHeight: 40
        leftPadding: 14
        rightPadding: 8
        background: Rectangle {
            radius: 12
            color: parent.opened ? window.activeSurface : parent.hovered ? window.hoverSurface : "transparent"
            border.width: parent.opened ? 1 : 0
            border.color: parent.opened ? (window.darkTheme ? "#536CCB" : "#8799E8") : "transparent"
        }
        contentItem: RowLayout {
            spacing: 8
            Label { text: parent.parent.label; color: window.textPrimary; font.pixelSize: 11; font.weight: Font.DemiBold }
            Label { text: parent.parent.detail; color: window.textMuted; font.pixelSize: 10 }
            Item { Layout.fillWidth: true }
            Rectangle {
                Layout.preferredWidth: 26
                Layout.preferredHeight: 26
                radius: 8
                color: parent.parent.opened ? (window.darkTheme ? "#283865" : "#DDE4FF") : window.panelAlt
                border.color: window.outline
                Label {
                    anchors.centerIn: parent
                    text: parent.parent.parent.opened ? "—" : "↗"
                    color: parent.parent.parent.opened ? window.primary : window.textSecondary
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }
            }
        }
    }

    component ModeButton: Button {
        required property string modeName
        required property string label
        Layout.fillWidth: true
        Layout.preferredHeight: 34
        onClicked: companion.set_output_mode(modeName)
        background: Rectangle {
            radius: 9
            color: companion.outputMode === parent.modeName ? "#5068E8" : parent.hovered ? window.hoverSurface : window.panelAlt
            border.color: companion.outputMode === parent.modeName ? "#7589FF" : window.outline
        }
        contentItem: Label { text: parent.label; color: companion.outputMode === parent.modeName ? "white" : window.textSecondary; font.pixelSize: 10; font.weight: Font.DemiBold; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
    }

    component DarkField: TextField {
        Layout.fillWidth: true
        Layout.preferredHeight: 38
        color: window.textPrimary
        placeholderTextColor: window.textMuted
        selectionColor: window.primary
        font.pixelSize: 11
        leftPadding: 12; rightPadding: 12
        background: Rectangle { radius: 10; color: window.fieldSurface; border.color: parent.activeFocus ? "#596FE3" : window.outline }
    }

    component SerialPortCombo: ComboBox {
        id: portControl
        Layout.fillWidth: true
        Layout.preferredHeight: 38
        model: companion.usbPorts
        currentIndex: companion.usbPorts.indexOf(companion.usbPort)
        displayText: currentIndex >= 0 ? currentText : companion.usbPort.length ? companion.usbPort + qsTr("  ·  unavailable") : count > 0 ? qsTr("Select COM port") : qsTr("No COM ports found")
        onActivated: companion.set_usb_port(currentText)
        leftPadding: 12; rightPadding: 34
        contentItem: Label {
            text: portControl.displayText
            color: portControl.currentIndex >= 0 ? window.textPrimary : window.textMuted
            font.pixelSize: 11
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        indicator: Label {
            x: portControl.width - width - 12; anchors.verticalCenter: parent.verticalCenter
            text: "⌄"; color: window.textSecondary; font.pixelSize: 15
        }
        background: Rectangle {
            radius: 10; color: window.fieldSurface
            border.color: portControl.activeFocus ? "#596FE3" : window.outline
        }
        delegate: ItemDelegate {
            width: portControl.width - 12
            height: 34
            text: modelData
            highlighted: portControl.highlightedIndex === index
            background: Rectangle { radius: 8; color: parent.highlighted ? window.activeSurface : parent.hovered ? window.hoverSurface : "transparent" }
            contentItem: Label { text: parent.text; color: window.textPrimary; font.pixelSize: 11; verticalAlignment: Text.AlignVCenter; leftPadding: 7 }
        }
        popup: Popup {
            y: portControl.height + 4
            width: portControl.width
            implicitHeight: Math.min(contentItem.implicitHeight + 12, 220)
            padding: 6
            contentItem: ListView {
                clip: true
                implicitHeight: contentHeight
                model: portControl.popup.visible ? portControl.delegateModel : null
                currentIndex: portControl.highlightedIndex
                ScrollIndicator.vertical: ScrollIndicator { }
            }
            background: Rectangle { radius: 11; color: window.panel; border.color: window.outline }
        }
    }

    Rectangle {
        id: frame
        anchors.fill: parent
        radius: window.visibility === Window.Maximized ? 0 : 15
        color: window.surface
        border.color: window.darkTheme ? "#2A3647" : "#C9D4E1"
        border.width: 1
        clip: true

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            Rectangle {
                id: titleBar
                Layout.fillWidth: true
                Layout.preferredHeight: 42
                Layout.maximumHeight: 42
                color: window.titleSurface
                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 8; spacing: 9
                    Image {
                        Layout.minimumWidth: 27
                        Layout.preferredWidth: 27
                        Layout.maximumWidth: 27
                        Layout.minimumHeight: 27
                        Layout.preferredHeight: 27
                        Layout.maximumHeight: 27
                        source: "qrc:/qt/qml/MotionBridge/App/assets/icons/motion-bridge.svg"
                        sourceSize.width: 72
                        sourceSize.height: 72
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        mipmap: true
                    }
                    Label { text: "Motion Bridge"; color: window.textPrimary; font.pixelSize: 12; font.weight: Font.DemiBold }
                    Label { text: qsTr("GAME MOTION · MULTI-AXIS"); color: window.textMuted; font.pixelSize: 8; font.letterSpacing: 1.1 }
                    Item { Layout.fillWidth: true }
                    WindowButton {
                        id: languageButton
                        glyph: languageController.effectiveLanguage === "zh_CN" ? "中" : "EN"
                        glyphSize: languageController.effectiveLanguage === "zh_CN" ? 12 : 10
                        onClicked: languageMenu.popup(languageButton,
                                                       languageButton.width - languageMenu.width,
                                                       languageButton.height + 4)
                        ToolTip.visible: hovered
                        ToolTip.text: qsTr("Language")
                        Menu {
                            id: languageMenu
                            width: 168
                            padding: 7
                            margins: 6
                            background: Rectangle {
                                radius: 12
                                color: window.panel
                                border.color: window.outline
                            }
                            LanguageOption {
                                languageCode: "auto"
                                optionText: qsTr("Follow system")
                            }
                            LanguageOption {
                                languageCode: "zh_CN"
                                optionText: "中文"
                            }
                            LanguageOption {
                                languageCode: "en"
                                optionText: "English"
                            }
                        }
                    }
                    WindowButton {
                        glyph: window.darkTheme ? "☀" : "☾"
                        onClicked: companion.set_theme(window.darkTheme ? "light" : "dark")
                        ToolTip.visible: hovered
                        ToolTip.text: window.darkTheme ? qsTr("Switch to light theme") : qsTr("Switch to dark theme")
                    }
                    WindowButton { glyph: "—"; onClicked: window.showMinimized() }
                    WindowButton { glyph: "✕"; hoverColor: "#B84350"; onClicked: window.close() }
                }
                MouseArea {
                    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom
                    // Keep the drag layer away from all four window controls;
                    // overlap here made the left-most hover target intermittent.
                    anchors.rightMargin: 216
                    acceptedButtons: Qt.LeftButton
                    onPressed: window.startSystemMove()
                    onDoubleClicked: window.visibility === Window.Maximized ? window.showNormal() : window.showMaximized()
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 82
                Layout.maximumHeight: 82
                color: window.headerSurface
                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: 20; anchors.rightMargin: 20; spacing: 16
                    ColumnLayout {
                        Layout.preferredWidth: 208; spacing: 2
                        Label { text: qsTr("Live control"); color: window.textPrimary; font.pixelSize: 18; font.bold: true }
                        Label { text: companion.actionName.length ? companion.actionName : "Operation Lovecraft: Fallen Doll"; color: window.textMuted; elide: Text.ElideRight; Layout.fillWidth: true; font.pixelSize: 10 }
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 9
                        Item { Layout.fillWidth: true }
                        StatusChip { caption: qsTr("STREAM"); value: companion.streamConnected ? qsTr("ONLINE") : qsTr("WAITING"); accent: companion.streamConnected ? "#58D9FA" : "#F1B865" }
                        StatusChip { caption: qsTr("MOTION"); value: window.motionStateLabel(companion.motionState); accent: companion.motionState === "active" ? "#56E3B1" : "#7E8CA2" }
                        StatusChip { caption: qsTr("DEVICE"); value: companion.armed ? qsTr("ARMED") : companion.outputMode === "none" ? qsTr("OFF") : companion.outputMode.toUpperCase(); accent: companion.armed ? "#56E3B1" : "#F1B865" }
                    }
                    Button {
                        Layout.preferredWidth: 128; Layout.preferredHeight: 42
                        text: companion.armed ? qsTr("STOP OUTPUT") : qsTr("ARM OUTPUT")
                        onClicked: companion.set_armed(!companion.armed)
                        background: Rectangle { radius: 12; color: companion.armed ? "#DA5361" : window.primary; opacity: parent.down ? 0.78 : 1.0 }
                        contentItem: Label { text: parent.text; color: "white"; font.pixelSize: 11; font.bold: true; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 62
                Layout.maximumHeight: 62
                color: window.footerSurface
                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: 16; anchors.rightMargin: 18; spacing: 6
                    DisclosureButton { label: qsTr("Device connection"); detail: qsTr("USB · Wi-Fi · Intiface"); opened: window.connectionExpanded; onClicked: window.toggleConnection() }
                    DisclosureButton { label: qsTr("Motion tuning"); detail: "L0 · L1 · L2 · R0 · R1 · R2"; opened: window.tuningExpanded; onClicked: window.toggleTuning() }
                    ViewerButton { label: qsTr("3D preview"); detail: qsTr("Separate window"); opened: previewWindow.visible; onClicked: window.togglePreview() }
                    Label { text: qsTr("OUTPUT SAFE"); color: window.textMuted; font.pixelSize: 9; font.bold: true; font.letterSpacing: 0.8; Layout.leftMargin: 10 }
                }
            }

            Rectangle {
                id: expandedArea
                visible: window.expanded
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                color: window.darkTheme ? "#090E16" : "#EDF2F7"

                ColumnLayout {
                    id: expandedContent
                    x: 20; y: 18
                    width: parent.width - 40
                    spacing: 14

                    RowLayout {
                        visible: window.connectionExpanded
                        Layout.fillWidth: true
                        Layout.preferredHeight: 250
                        spacing: 14
                        Rectangle {
                            visible: window.connectionExpanded
                            Layout.fillWidth: true
                            Layout.minimumWidth: 354
                            Layout.maximumWidth: 920
                            Layout.alignment: Qt.AlignHCenter
                            Layout.fillHeight: true
                            radius: 16; color: window.panel; border.color: window.outline
                            ColumnLayout {
                                anchors.fill: parent; anchors.margins: 18; spacing: 11
                                RowLayout { Layout.fillWidth: true
                                    ColumnLayout { spacing: 2
                                        Label { text: qsTr("Device connection"); color: window.textPrimary; font.pixelSize: 16; font.bold: true }
                                        Label { text: qsTr("One transport at a time"); color: window.textMuted; font.pixelSize: 10 }
                                    }
                                    Item { Layout.fillWidth: true }
                                    Rectangle { width: 70; height: 24; radius: 12; color: companion.armed ? (window.darkTheme ? "#173B34" : "#DDF7ED") : window.panelAlt; border.color: window.outline
                                        Label { anchors.centerIn: parent; text: companion.armed ? qsTr("ARMED") : qsTr("SAFE"); color: companion.armed ? (window.darkTheme ? "#5BE4B5" : "#167A5B") : window.textMuted; font.pixelSize: 9; font.bold: true }
                                    }
                                }
                                RowLayout { Layout.fillWidth: true; spacing: 6
                                    ModeButton { modeName: "none"; label: qsTr("OFF") }
                                    ModeButton { modeName: "usb"; label: "USB" }
                                    ModeButton { modeName: "wifi"; label: "WI-FI" }
                                    ModeButton { modeName: "intiface"; label: "INTIFACE" }
                                }
                                GridLayout {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    columns: 2
                                    columnSpacing: 10
                                    rowSpacing: 8

                                    ColumnLayout {
                                        Layout.fillWidth: true; spacing: 4
                                        Label { text: qsTr("USB PORT"); color: window.textMuted; font.pixelSize: 8; font.bold: true; font.letterSpacing: 0.7 }
                                        RowLayout {
                                            Layout.fillWidth: true; spacing: 7
                                            SerialPortCombo { }
                                            Button {
                                                Layout.preferredWidth: 38; Layout.preferredHeight: 38
                                                text: "↻"; onClicked: companion.refresh_usb_ports()
                                                background: Rectangle { radius: 10; color: parent.hovered ? window.hoverSurface : window.panelAlt; border.color: window.outline }
                                                contentItem: Label { text: parent.text; color: window.textSecondary; font.pixelSize: 15; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                                ToolTip.visible: hovered; ToolTip.text: qsTr("Refresh serial ports")
                                            }
                                        }
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true; spacing: 4
                                        Label { text: qsTr("WI-FI HOST"); color: window.textMuted; font.pixelSize: 8; font.bold: true; font.letterSpacing: 0.7 }
                                        DarkField { text: companion.wifiHost; placeholderText: qsTr("Wi-Fi host"); onEditingFinished: companion.set_wifi_endpoint(text, companion.wifiPort) }
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true; spacing: 4
                                        Label { text: qsTr("INTIFACE URL"); color: window.textMuted; font.pixelSize: 8; font.bold: true; font.letterSpacing: 0.7 }
                                        DarkField { text: companion.intifaceUrl; placeholderText: qsTr("Intiface Desktop URL"); onEditingFinished: companion.set_intiface_url(text) }
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true; spacing: 4
                                        Label { text: qsTr("SAFETY"); color: window.textMuted; font.pixelSize: 8; font.bold: true; font.letterSpacing: 0.7 }
                                        Button {
                                            Layout.fillWidth: true; Layout.preferredHeight: 38; text: qsTr("CENTER & DISARM")
                                            onClicked: companion.emergency_stop()
                                            background: Rectangle { radius: 10; color: parent.hovered ? window.hoverSurface : window.panelAlt; border.color: window.outline }
                                            contentItem: Label { text: parent.text; color: window.textSecondary; font.pixelSize: 10; font.bold: true; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    RowLayout {
                        visible: window.tuningExpanded
                        Layout.fillWidth: true
                        Label { text: qsTr("Motion tuning"); color: window.textPrimary; font.pixelSize: 16; font.bold: true }
                        Label { text: qsTr("Device-side response · raw game motion stays unchanged"); color: window.textMuted; font.pixelSize: 10; Layout.leftMargin: 7 }
                        Item { Layout.fillWidth: true }
                    }
                    GridLayout {
                        visible: window.tuningExpanded
                        Layout.fillWidth: true
                        columns: width > 940 ? 3 : 2
                        columnSpacing: 11; rowSpacing: 11
                        AxisCard { darkTheme: window.darkTheme; axisIndex: 0; axisName: qsTr("L0  STROKE"); axisValue: companion.deviceAxes[0]; gain: companion.axisGains[0]; outputMinimum: companion.axisMinimums[0]; outputMaximum: companion.axisMaximums[0] }
                        AxisCard { darkTheme: window.darkTheme; axisIndex: 1; axisName: qsTr("L1  SURGE"); axisValue: companion.deviceAxes[1]; gain: companion.axisGains[1]; outputMinimum: companion.axisMinimums[1]; outputMaximum: companion.axisMaximums[1] }
                        AxisCard { darkTheme: window.darkTheme; axisIndex: 2; axisName: qsTr("L2  SWAY"); axisValue: companion.deviceAxes[2]; gain: companion.axisGains[2]; outputMinimum: companion.axisMinimums[2]; outputMaximum: companion.axisMaximums[2] }
                        AxisCard { darkTheme: window.darkTheme; axisIndex: 3; axisName: qsTr("R0  TWIST"); axisValue: companion.deviceAxes[3]; gain: companion.axisGains[3]; outputMinimum: companion.axisMinimums[3]; outputMaximum: companion.axisMaximums[3] }
                        AxisCard { darkTheme: window.darkTheme; axisIndex: 4; axisName: qsTr("R1  ROLL"); axisValue: companion.deviceAxes[4]; gain: companion.axisGains[4]; outputMinimum: companion.axisMinimums[4]; outputMaximum: companion.axisMaximums[4] }
                        AxisCard { darkTheme: window.darkTheme; axisIndex: 5; axisName: qsTr("R2  PITCH"); axisValue: companion.deviceAxes[5]; gain: companion.axisGains[5]; outputMinimum: companion.axisMinimums[5]; outputMaximum: companion.axisMaximums[5] }
                    }
                    Item { Layout.preferredHeight: 4 }
                }
            }
        }
    }

    Window {
        id: previewWindow
        width: 520
        height: 500
        minimumWidth: 420
        minimumHeight: 390
        visible: false
        title: qsTr("3D preview")
        color: "transparent"
        property bool alwaysOnTop: false
        flags: alwaysOnTop
               ? (Qt.Window | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint)
               : (Qt.Window | Qt.FramelessWindowHint)

        Rectangle {
            anchors.fill: parent
            radius: 14
            color: window.surface
            border.width: 1
            border.color: window.darkTheme ? "#2A3647" : "#C9D4E1"
            clip: true

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                Rectangle {
                    id: previewTitleBar
                    Layout.fillWidth: true
                    Layout.preferredHeight: 42
                    color: window.titleSurface

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 8
                        spacing: 8

                        Rectangle { width: 7; height: 7; radius: 4; color: window.cyan }
                        Label {
                            text: qsTr("SR6 / OSR 3D preview")
                            color: window.textPrimary
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                        }
                        Item { Layout.fillWidth: true }
                        Button {
                            Layout.preferredWidth: 74
                            Layout.preferredHeight: 28
                            text: qsTr("TOP")
                            checkable: true
                            checked: previewWindow.alwaysOnTop
                            onClicked: {
                                previewWindow.alwaysOnTop = checked
                                Qt.callLater(function() {
                                    previewWindow.show()
                                    previewWindow.raise()
                                    previewWindow.requestActivate()
                                })
                            }
                            background: Rectangle {
                                radius: 8
                                color: parent.checked ? window.activeSurface
                                                      : parent.hovered ? window.hoverSurface : "transparent"
                                border.width: parent.checked ? 1 : 0
                                border.color: window.darkTheme ? "#536CCB" : "#8799E8"
                            }
                            contentItem: Label {
                                text: parent.text
                                color: parent.checked ? window.primary : window.textSecondary
                                font.pixelSize: 9
                                font.weight: Font.DemiBold
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            ToolTip.visible: hovered
                            ToolTip.text: qsTr("Always on top")
                        }
                        WindowButton { glyph: "✕"; hoverColor: "#B84350"; onClicked: previewWindow.hide() }
                    }

                    MouseArea {
                        anchors.fill: parent
                        anchors.rightMargin: 132
                        acceptedButtons: Qt.LeftButton
                        onPressed: previewWindow.startSystemMove()
                    }
                }

                OsrPreview {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.margins: 10
                    darkTheme: window.darkTheme
                    l0: companion.deviceAxes[0]; l1: companion.deviceAxes[1]; l2: companion.deviceAxes[2]
                    r0: companion.deviceAxes[3]; r1: companion.deviceAxes[4]; r2: companion.deviceAxes[5]
                }
            }
        }

        MouseArea { z: 20; anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom; width: 6; cursorShape: Qt.SizeHorCursor; onPressed: previewWindow.startSystemResize(Qt.LeftEdge) }
        MouseArea { z: 20; anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom; width: 6; cursorShape: Qt.SizeHorCursor; onPressed: previewWindow.startSystemResize(Qt.RightEdge) }
        MouseArea { z: 20; anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; height: 5; cursorShape: Qt.SizeVerCursor; onPressed: previewWindow.startSystemResize(Qt.TopEdge) }
        MouseArea { z: 20; anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 6; cursorShape: Qt.SizeVerCursor; onPressed: previewWindow.startSystemResize(Qt.BottomEdge) }
    }

    // Native resizing keeps the frameless window behaving like a normal Windows app.
    MouseArea { z: 20; anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom; width: 6; cursorShape: Qt.SizeHorCursor; onPressed: window.startSystemResize(Qt.LeftEdge) }
    MouseArea { z: 20; anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom; width: 6; cursorShape: Qt.SizeHorCursor; onPressed: window.startSystemResize(Qt.RightEdge) }
    MouseArea { z: 20; anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; height: 5; cursorShape: Qt.SizeVerCursor; onPressed: window.startSystemResize(Qt.TopEdge) }
    MouseArea { z: 20; anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 6; cursorShape: Qt.SizeVerCursor; onPressed: window.startSystemResize(Qt.BottomEdge) }
}
