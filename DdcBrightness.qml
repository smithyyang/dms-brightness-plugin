import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    property bool loading: false
    property bool hasScanned: false

    function startScan(forceRefresh) {
        if (procScan.running)
            return

        if (!forceRefresh && hasScanned)
            return

        hasScanned = true
        loading = true
        procScan.running = true
    }

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
            "  detect_output=$(timeout 3s ddcutil detect --terse 2>/dev/null)\n" +
            "  detect_status=$?\n" +
            "  if [ \"$detect_status\" -ne 0 ]; then\n" +
            "    exit 1\n" +
            "  fi\n" +
            "  current_bus=\"\"\n" +
            "  current_name=\"\"\n" +
            "  current_valid=0\n" +
            "  while IFS= read -r line; do\n" +
            "    case \"$line\" in\n" +
            "      \"Invalid display\"*)\n" +
            "        current_bus=\"\"\n" +
            "        current_name=\"\"\n" +
            "        current_valid=0\n" +
            "        ;;\n" +
            "      \"Display \"*)\n" +
            "        current_bus=\"\"\n" +
            "        current_name=\"\"\n" +
            "        current_valid=1\n" +
            "        ;;\n" +
            "      *\"I2C bus:\"*)\n" +
            "        current_bus=$(printf '%s' \"$line\" | awk -F'/dev/i2c-' '{print $2}' | xargs)\n" +
            "        current_name=\"\"\n" +
            "        ;;\n" +
            "      *\"Monitor:\"*)\n" +
            "        current_name=$(printf '%s' \"$line\" | awk -F'Monitor:' '{print $2}' | sed 's/^ *//' | sed 's/:$//')\n" +
            "        if [ \"$current_valid\" -eq 1 ] && [ -n \"$current_bus\" ]; then\n" +
            "          val=$(timeout 2s ddcutil getvcp 10 --bus \"$current_bus\" --terse 2>/dev/null | awk '{print $4}')\n" +
            "          [ -z \"$val\" ] && val=-1\n" +
            "          [ -z \"$current_name\" ] && current_name=\"External Display (Bus $current_bus)\"\n" +
            "          res=\"$res{\\\"id\\\":\\\"$current_bus\\\",\\\"name\\\":\\\"$current_name\\\",\\\"type\\\":\\\"ddc\\\",\\\"level\\\":$val},\"\n" +
            "        fi\n" +
            "        ;;\n" +
            "    esac\n" +
            "  done <<< \"$detect_output\"\n" +
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
                        var previous = {}
                        for (var i = 0; i < monitorsModel.count; i++) {
                            var existing = monitorsModel.get(i)
                            previous[existing.type + ":" + existing.id] = existing
                        }

                        if (arr.length === 0 && monitorsModel.count > 0) {
                            console.warn("DDC scan returned no monitors, keeping previous results")
                            return
                        }

                        monitorsModel.clear()
                        for (var i = 0; i < arr.length; i++) {
                            var item = arr[i]
                            var existingMonitor = previous[item.type + ":" + item.id]

                            if (item.level < 0)
                                item.level = existingMonitor ? existingMonitor.level : 50

                            item.busy = existingMonitor ? existingMonitor.busy : false
                            monitorsModel.append(item)
                        }
                    } catch(e) {
                        console.warn("DDC Parse Error:", e, cleanText)
                    }
                }
            }
        }

        onExited: exitCode => {
            if (exitCode !== 0)
                console.warn("DDC scan failed with code:", exitCode)

            root.loading = false
        }
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
            Component.onCompleted: root.startScan(false)

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
                            property int queuedLevel: -1
                            property int applyingLevel: -1

                            function currentMonitor() {
                                if (monitorDelegate.index < 0 || monitorDelegate.index >= monitorsModel.count)
                                    return null

                                var current = monitorsModel.get(monitorDelegate.index)
                                if (!current || current.id !== monitorDelegate.id || current.type !== monitorDelegate.type)
                                    return null

                                return current
                            }

                            function setBusyState(value) {
                                if (currentMonitor())
                                    monitorsModel.setProperty(monitorDelegate.index, "busy", value)
                            }

                            function runSetter(level) {
                                var current = currentMonitor()
                                if (!current)
                                    return

                                applyingLevel = level
                                queuedLevel = -1

                                if (current.type === "ddc") {
                                    setterProc.command = ["timeout", "3s", "ddcutil", "setvcp", "10", String(level), "--bus", current.id, "--noverify"]
                                } else {
                                    setterProc.command = ["brightnessctl", "-d", current.id, "s", String(level) + "%"]
                                }

                                setterProc.running = true
                            }

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
                                    var current = monitorDelegate.currentMonitor()
                                    if (!current)
                                        return

                                    if (setterProc.running) {
                                        monitorDelegate.queuedLevel = current.level
                                        return
                                    }

                                    monitorDelegate.runSetter(current.level)
                                }
                            }

                            Process {
                                id: setterProc
                                onStarted: monitorDelegate.setBusyState(true)
                                onExited: exitCode => {
                                    if (exitCode !== 0)
                                        console.warn("Brightness apply failed for", monitorDelegate.name, "with code", exitCode)

                                    var nextLevel = monitorDelegate.queuedLevel
                                    monitorDelegate.queuedLevel = -1

                                    if (nextLevel >= 0 && nextLevel !== monitorDelegate.applyingLevel) {
                                        monitorDelegate.runSetter(nextLevel)
                                        return
                                    }

                                    monitorDelegate.applyingLevel = -1
                                    monitorDelegate.setBusyState(false)
                                }
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
                        onClicked: root.startScan(true)
                    }
                }
            }
        }
    }
}
