import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    property bool loading: true

    ListModel {
        id: monitorsModel
    }

    Process {
        id: procScan
        command: ["bash", "-c", "res=\"[\"\n" +
            "if command -v brightnessctl &>/dev/null; then\n" +
            "  for dev in $(brightnessctl -l | awk '/backlight/ {print $2}' | tr -d \"':\"); do\n" +
            "    pct=$(brightnessctl -d \"$dev\" g)\n" +
            "    max=$(brightnessctl -d \"$dev\" m)\n" +
            "    if [ -n \"$pct\" ] && [ -n \"$max\" ] && [ \"$max\" -gt 0 ]; then\n" +
            "      val=$(( pct * 100 / max ))\n" +
            "      res=\"$res{\\\"id\\\":\\\"$dev\\\",\\\"name\\\":\\\"Internal Display\\\",\\\"type\\\":\\\"sysfs\\\",\\\"level\\\":$val},\"\n" +
            "    fi\n" +
            "  done\n" +
            "fi\n" +
            "if command -v ddcutil &>/dev/null; then\n" +
            "  for bus in $(ddcutil detect --terse 2>/dev/null | awk -F'-' '/I2C bus:/ {print $2}'); do\n" +
            "    val=$(ddcutil getvcp 10 --bus \"$bus\" --terse 2>/dev/null | awk '{print $4}')\n" +
            "    if [ -n \"$val\" ]; then\n" +
            "      name=$(ddcutil detect --bus \"$bus\" 2>/dev/null | awk -F':' '/Model:/ {print $2}' | xargs)\n" +
            "      [ -z \"$name\" ] && name=\"External Display (Bus $bus)\"\n" +
            "      res=\"$res{\\\"id\\\":\\\"$bus\\\",\\\"name\\\":\\\"$name\\\",\\\"type\\\":\\\"ddc\\\",\\\"level\\\":$val},\"\n" +
            "    fi\n" +
            "  done\n" +
            "fi\n" +
            "res=\"${res%,}]\"\n" +
            "[ \"$res\" = \"]\" ] && res=\"[]\"\n" +
            "echo \"$res\""
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                var cleanText = text.trim()
                if (cleanText) {
                    try {
                        var arr = JSON.parse(cleanText)
                        monitorsModel.clear()
                        for (var i = 0; i < arr.length; i++) {
                            arr[i].busy = false
                            monitorsModel.append(arr[i])
                        }
                    } catch(e) {
                        console.warn("DDC Parse Error:", e, cleanText)
                    }
                }
                root.loading = false
            }
        }
    }

    Component.onCompleted: {
        procScan.running = true
    }

    horizontalBarPill: Component {
        Item {
            implicitWidth: Theme.iconSize
            implicitHeight: Theme.iconSize
            DankIcon {
                property int avgLevel: monitorsModel.count > 0 ? monitorsModel.get(0).level : 50
                name: avgLevel > 66 ? "brightness_high" : avgLevel > 33 ? "brightness_medium" : "brightness_low"
                size: Theme.iconSize * 0.85
                anchors.centerIn: parent
            }
        }
    }

    popoutWidth: 360
    popoutHeight: mainCol.implicitHeight + Theme.spacingL * 2 + 50

    popoutContent: Component {
        PopoutComponent {
            headerText: "Brightness Control"
            showCloseButton: true

            Item {
                width: parent.width
                implicitHeight: mainCol.implicitHeight

                Column {
                    id: mainCol
                    width: parent.width
                    spacing: Theme.spacingL

                    StyledText {
                        visible: root.loading
                        text: "Scanning for displays..."
                        color: Theme.primary
                        font.pixelSize: Theme.fontSizeSmall
                        horizontalAlignment: Text.AlignHCenter
                        width: parent.width
                    }

                    StyledText {
                        visible: !root.loading && monitorsModel.count === 0
                        text: "No controllable displays found"
                        color: Theme.error
                        font.pixelSize: Theme.fontSizeSmall
                        horizontalAlignment: Text.AlignHCenter
                        width: parent.width
                    }

                    Repeater {
                        model: monitorsModel

                        delegate: Column {
                            id: monitorDelegate
                            // 强制声明属性，防止被内部的 Repeater 作用域覆盖
                            required property int index
                            required property string name
                            required property string type
                            required property string id
                            required property int level
                            required property bool busy

                            width: parent.width
                            spacing: Theme.spacingM

                            Row {
                                width: parent.width
                                spacing: Theme.spacingS

                                StyledText { text: monitorDelegate.name; font.pixelSize: Theme.fontSizeMedium; color: Theme.surfaceText; font.bold: true }
                                StyledText { text: monitorDelegate.type === "ddc" ? "(DDC)" : "(Internal)"; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceTextMedium; anchors.verticalCenter: parent.verticalCenter }
                                StyledText { visible: monitorDelegate.busy; text: " ⏳ Applying..."; font.pixelSize: Theme.fontSizeSmall; color: Theme.primary; anchors.verticalCenter: parent.verticalCenter }
                            }

                            Row {
                                width: parent.width
                                spacing: Theme.spacingM

                                DankIcon { name: "brightness_low"; size: 18; anchors.verticalCenter: parent.verticalCenter }

                                DankSlider {
                                    id: slider
                                    width: parent.width - 18 - 18 - 36 - Theme.spacingM * 3
                                    minimum: 0
                                    maximum: 100
                                    showValue: false
                                    anchors.verticalCenter: parent.verticalCenter
                                    value: monitorDelegate.level

                                    onSliderValueChanged: (v) => {
                                        // 使用 monitorDelegate.index 绝对锁定屏幕
                                        monitorsModel.setProperty(monitorDelegate.index, "level", Math.round(v))
                                        debounceTimer.restart()
                                    }
                                }

                                DankIcon { name: "brightness_high"; size: 18; anchors.verticalCenter: parent.verticalCenter }
                                StyledText { text: monitorDelegate.level + "%"; font.pixelSize: Theme.fontSizeSmall; width: 36; anchors.verticalCenter: parent.verticalCenter }
                            }

                            Row {
                                width: parent.width
                                spacing: Theme.spacingS

                                Repeater {
                                    model: [0, 25, 50, 75, 100]
                                    DankButton {
                                        text: modelData + "%"
                                        width: (parent.width - Theme.spacingS * 4) / 5
                                        onClicked: {
                                            // 使用 monitorDelegate.index 绝对锁定屏幕，绝不串台
                                            monitorsModel.setProperty(monitorDelegate.index, "level", modelData)
                                            debounceTimer.restart()
                                        }
                                    }
                                }
                            }

                            Timer {
                                id: debounceTimer
                                interval: 300
                                repeat: false
                                onTriggered: {
                                    // 在执行命令前，强行抓取最新的 model 数值
                                    var curLevel = monitorsModel.get(monitorDelegate.index).level
                                    var curId = monitorsModel.get(monitorDelegate.index).id
                                    var curType = monitorsModel.get(monitorDelegate.index).type
                                    
                                    if (curType === "ddc") {
                                        setterProc.command = ["ddcutil", "setvcp", "10", String(curLevel), "--bus", curId, "--noverify"]
                                    } else {
                                        setterProc.command = ["brightnessctl", "-d", curId, "s", String(curLevel) + "%"]
                                    }
                                    
                                    if (!setterProc.running) {
                                        setterProc.running = true
                                    }
                                }
                            }

                            Process {
                                id: setterProc
                                onStarted: monitorsModel.setProperty(monitorDelegate.index, "busy", true)
                                onExited: monitorsModel.setProperty(monitorDelegate.index, "busy", false)
                            }

                            Item {
                                width: parent.width
                                height: Theme.spacingL
                                visible: monitorDelegate.index < monitorsModel.count - 1
                                Rectangle {
                                    width: parent.width
                                    height: 1
                                    color: Theme.surfaceText
                                    opacity: 0.1
                                    anchors.centerIn: parent
                                }
                            }
                        }
                    }

                    DankButton {
                        visible: !root.loading
                        text: "Refresh"
                        width: parent.width
                        onClicked: {
                            root.loading = true
                            monitorsModel.clear()
                            procScan.running = true
                        }
                    }
                }
            }
        }
    }
}
