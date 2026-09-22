pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

PanelWindow {
    id: root

    required property var windowByAddress
    required property bool overviewOpen
    required property bool livePreviews

    signal closeRequested()

    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(screen)
    readonly property bool monitorFocused: monitor?.id === Hyprland.focusedMonitor?.id
    readonly property var workspaceEntries: entriesForMonitor()
    property int selectedIndex: 0
    property int dragTargetWorkspace: -1

    readonly property real outerMargin: 40
    readonly property real cardGap: 24
    readonly property int columnCount: Math.max(1, Math.ceil(Math.sqrt(
        Math.max(1, workspaceEntries.length) * Math.max(1, width) / Math.max(1, height)
    )))
    readonly property real cardWidth: Math.max(220, Math.min(
        520,
        (Math.max(1, width) - 2 * outerMargin - cardGap * (columnCount - 1)) / columnCount
    ))
    readonly property real cardHeight: 38 + (cardWidth - 24) * Math.max(1, screen?.height ?? 1) / Math.max(1, screen?.width ?? 1)

    function entriesForMonitor() {
        if (!monitor)
            return [];

        const all = Hyprland.workspaces.values ?? [];
        const entries = all
            .filter(workspace => workspace.id > 0 && workspace.monitor?.id === monitor.id)
            .map(workspace => ({
                id: workspace.id,
                name: workspace.name,
                workspace: workspace,
                empty: false
            }))
            .sort((a, b) => a.id - b.id);

        if (monitorFocused) {
            let nextId = 1;
            for (const workspace of all) {
                if (workspace.id >= nextId)
                    nextId = workspace.id + 1;
            }
            entries.push({
                id: nextId,
                name: `${nextId}`,
                workspace: null,
                empty: true
            });
        }

        return entries;
    }

    function windowsForWorkspace(workspaceId) {
        return (ToplevelManager.toplevels.values ?? []).filter(toplevel => {
            const hyprland = toplevel.HyprlandToplevel;
            const data = dataFor(toplevel);
            const id = hyprland.workspace?.id ?? data.workspace?.id;
            return Number(id) === workspaceId && addressFor(toplevel) !== "";
        });
    }

    function addressFor(toplevel) {
        const address = `${toplevel?.HyprlandToplevel?.address ?? ""}`;
        if (address === "")
            return "";
        return address.startsWith("0x") ? address : `0x${address}`;
    }

    function dataFor(toplevel) {
        return windowByAddress[addressFor(toplevel)]
            ?? toplevel?.HyprlandToplevel?.lastIpcObject
            ?? ({});
    }

    function workspaceBounds(workspaceId) {
        const monitorData = monitor?.lastIpcObject ?? ({});
        let minX = Number(monitorData.x ?? 0);
        let minY = Number(monitorData.y ?? 0);
        let maxX = minX + Math.max(1, Number(screen?.width ?? 1));
        let maxY = minY + Math.max(1, Number(screen?.height ?? 1));

        for (const toplevel of windowsForWorkspace(workspaceId)) {
            const data = dataFor(toplevel);
            if (!data.at || !data.size)
                continue;
            const x = Number(data.at[0]);
            const y = Number(data.at[1]);
            const w = Math.max(1, Number(data.size[0]));
            const h = Math.max(1, Number(data.size[1]));
            minX = Math.min(minX, x);
            minY = Math.min(minY, y);
            maxX = Math.max(maxX, x + w);
            maxY = Math.max(maxY, y + h);
        }

        return {
            x: minX,
            y: minY,
            w: Math.max(1, maxX - minX),
            h: Math.max(1, maxY - minY)
        };
    }

    function selectDelta(delta) {
        if (workspaceEntries.length === 0)
            return;
        selectedIndex = (selectedIndex + delta + workspaceEntries.length) % workspaceEntries.length;
    }

    function resetSelection() {
        const activeId = monitor?.activeWorkspace?.id;
        const index = workspaceEntries.findIndex(entry => entry.id === activeId);
        selectedIndex = index >= 0 ? index : 0;
    }

    function activateWorkspace(workspaceId) {
        closeRequested();
        if (Hyprland.usingLua)
            Hyprland.dispatch(`hl.dsp.focus({ workspace = '${workspaceId}' })`);
        else
            Hyprland.dispatch(`workspace ${workspaceId}`);
    }

    function activateSelected() {
        const entry = workspaceEntries[selectedIndex];
        if (entry)
            activateWorkspace(entry.id);
    }

    function focusWindow(address) {
        if (address === "")
            return;
        closeRequested();
        if (Hyprland.usingLua)
            Hyprland.dispatch(`hl.dsp.focus({ window = 'address:${address}' })`);
        else
            Hyprland.dispatch(`focuswindow address:${address}`);
    }

    function moveWindow(address, workspaceId) {
        if (address === "" || workspaceId < 1)
            return;
        if (Hyprland.usingLua) {
            Hyprland.dispatch(
                `hl.dsp.window.move({ workspace = '${workspaceId}', follow = false, window = 'address:${address}' })`
            );
        } else {
            Hyprland.dispatch(`movetoworkspacesilent ${workspaceId}, address:${address}`);
        }
        Hyprland.refreshWorkspaces();
        Hyprland.refreshToplevels();
    }

    screen: modelData
    visible: overviewOpen
    color: "transparent"

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    WlrLayershell.namespace: "hyprland-grid-overview"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusiveZone: 0
    WlrLayershell.keyboardFocus: monitorFocused ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    onVisibleChanged: {
        if (visible) {
            resetSelection();
            focusDelay.restart();
        } else {
            dragTargetWorkspace = -1;
        }
    }

    onWorkspaceEntriesChanged: {
        if (selectedIndex >= workspaceEntries.length)
            selectedIndex = Math.max(0, workspaceEntries.length - 1);
    }

    Timer {
        id: focusDelay
        interval: 30
        repeat: false
        onTriggered: {
            if (root.monitorFocused)
                keySurface.forceActiveFocus();
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "#d9121721"

        Item {
            id: keySurface
            anchors.fill: parent
            focus: root.visible && root.monitorFocused

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    root.closeRequested();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    root.activateSelected();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Up
                           || event.key === Qt.Key_H || event.key === Qt.Key_K) {
                    root.selectDelta(-1);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down
                           || event.key === Qt.Key_L || event.key === Qt.Key_J) {
                    root.selectDelta(1);
                    event.accepted = true;
                }
            }

            WheelHandler {
                onWheel: event => {
                    root.selectDelta(event.angleDelta.y < 0 ? 1 : -1);
                    event.accepted = true;
                }
            }

            Flickable {
                id: viewport
                anchors.fill: parent
                anchors.margins: root.outerMargin
                clip: true
                contentWidth: Math.max(width, workspaceGrid.implicitWidth)
                contentHeight: Math.max(height, workspaceGrid.implicitHeight)
                boundsBehavior: Flickable.StopAtBounds

                Grid {
                    id: workspaceGrid
                    anchors.horizontalCenter: parent.horizontalCenter
                    columns: root.columnCount
                    columnSpacing: root.cardGap
                    rowSpacing: root.cardGap

                    Repeater {
                        model: root.workspaceEntries

                        delegate: Rectangle {
                            id: workspaceCard

                            required property var modelData
                            required property int index

                            readonly property int workspaceId: modelData.id
                            readonly property bool active: modelData.workspace?.active ?? false
                            readonly property bool selected: index === root.selectedIndex
                            readonly property var bounds: root.workspaceBounds(workspaceId)
                            readonly property real canvasWidth: width - 24
                            readonly property real canvasHeight: height - 50
                            readonly property real contentScale: Math.min(
                                canvasWidth / Math.max(1, bounds.w),
                                canvasHeight / Math.max(1, bounds.h)
                            )

                            width: root.cardWidth
                            height: root.cardHeight
                            radius: 14
                            color: active ? "#f0293445" : "#e61b2330"
                            border.width: root.dragTargetWorkspace === workspaceId || selected ? 3 : 1
                            border.color: root.dragTargetWorkspace === workspaceId
                                ? "#a6e3a1"
                                : selected ? "#89b4fa" : active ? "#74c7ec" : "#556275"
                            clip: false

                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 14
                                anchors.top: parent.top
                                anchors.topMargin: 8
                                text: workspaceCard.modelData.empty
                                    ? `Workspace ${workspaceCard.workspaceId} · empty`
                                    : `Workspace ${workspaceCard.modelData.name}`
                                color: "#f1f5f9"
                                font.pixelSize: 15
                                font.bold: workspaceCard.active
                            }

                            Rectangle {
                                id: canvas
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.margins: 12
                                height: workspaceCard.canvasHeight
                                radius: 9
                                color: "#b30b1018"
                                border.width: 1
                                border.color: "#354152"
                                clip: false

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: root.activateWorkspace(workspaceCard.workspaceId)
                                }

                                DropArea {
                                    anchors.fill: parent
                                    onEntered: root.dragTargetWorkspace = workspaceCard.workspaceId
                                    onExited: {
                                        if (root.dragTargetWorkspace === workspaceCard.workspaceId)
                                            root.dragTargetWorkspace = -1;
                                    }
                                }

                                Repeater {
                                    model: root.windowsForWorkspace(workspaceCard.workspaceId)

                                    delegate: Rectangle {
                                        id: windowTile

                                        required property var modelData
                                        required property int index

                                        readonly property var windowData: root.dataFor(modelData)
                                        readonly property string address: root.addressFor(modelData)
                                        readonly property real homeX: 6 + (Number(windowData.at?.[0] ?? workspaceCard.bounds.x) - workspaceCard.bounds.x)
                                            * workspaceCard.contentScale
                                        readonly property real homeY: 6 + (Number(windowData.at?.[1] ?? workspaceCard.bounds.y) - workspaceCard.bounds.y)
                                            * workspaceCard.contentScale
                                        readonly property real homeWidth: Math.max(42, Number(windowData.size?.[0] ?? 320) * workspaceCard.contentScale)
                                        readonly property real homeHeight: Math.max(30, Number(windowData.size?.[1] ?? 180) * workspaceCard.contentScale)

                                        function resetPosition() {
                                            x = homeX;
                                            y = homeY;
                                        }

                                        width: Math.min(homeWidth, canvas.width - homeX - 6)
                                        height: Math.min(homeHeight, canvas.height - homeY - 6)
                                        radius: 7
                                        color: "#303b4d"
                                        border.width: modelData.HyprlandToplevel.activated ? 3 : 1
                                        border.color: modelData.HyprlandToplevel.activated ? "#f9e2af" : "#8b9bb4"
                                        clip: true
                                        z: windowTile.Drag.active ? 1000 : 10 + index

                                        Drag.source: windowTile

                                        Component.onCompleted: resetPosition()
                                        onHomeXChanged: {
                                            if (!windowTile.Drag.active)
                                                resetPosition();
                                        }
                                        onHomeYChanged: {
                                            if (!windowTile.Drag.active)
                                                resetPosition();
                                        }

                                        Rectangle {
                                            anchors.fill: parent
                                            color: "#26303f"
                                        }

                                        ScreencopyView {
                                            anchors.fill: parent
                                            captureSource: root.overviewOpen && root.visible ? windowTile.modelData : null
                                            live: root.livePreviews
                                        }

                                        Rectangle {
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.bottom: parent.bottom
                                            height: Math.min(28, parent.height)
                                            color: "#b0000000"

                                            Text {
                                                anchors.fill: parent
                                                anchors.margins: 5
                                                text: `${windowTile.windowData.title ?? windowTile.modelData.title ?? "Window"}`
                                                color: "white"
                                                font.pixelSize: 11
                                                elide: Text.ElideRight
                                                verticalAlignment: Text.AlignVCenter
                                            }
                                        }

                                        MouseArea {
                                            id: dragArea
                                            anchors.fill: parent
                                            acceptedButtons: Qt.LeftButton
                                            drag.target: windowTile

                                            onPressed: mouse => {
                                                windowTile.Drag.active = true;
                                                windowTile.Drag.hotSpot.x = mouse.x;
                                                windowTile.Drag.hotSpot.y = mouse.y;
                                            }
                                            onClicked: root.focusWindow(windowTile.address)
                                            onReleased: {
                                                const targetWorkspace = root.dragTargetWorkspace;
                                                if (targetWorkspace > 0 && targetWorkspace !== workspaceCard.workspaceId)
                                                    root.moveWindow(windowTile.address, targetWorkspace);
                                                windowTile.Drag.active = false;
                                                root.dragTargetWorkspace = -1;
                                                windowTile.resetPosition();
                                            }
                                            onCanceled: {
                                                windowTile.Drag.active = false;
                                                root.dragTargetWorkspace = -1;
                                                windowTile.resetPosition();
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
