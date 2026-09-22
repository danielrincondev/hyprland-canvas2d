pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

Scope {
    id: shell

    property bool overviewOpen: false
    property bool livePreviews: false
    property var windowByAddress: ({})

    function refresh() {
        Hyprland.refreshMonitors();
        Hyprland.refreshWorkspaces();
        Hyprland.refreshToplevels();
        clientsProcess.running = true;
    }

    function setOpen(open) {
        if (overviewOpen === open)
            return;
        overviewOpen = open;
        if (open)
            refresh();
    }

    Variants {
        model: Quickshell.screens

        OverviewPanel {
            required property var modelData

            screen: modelData
            overviewOpen: shell.overviewOpen
            livePreviews: shell.livePreviews
            windowByAddress: shell.windowByAddress
            onCloseRequested: shell.setOpen(false)
        }
    }

    Process {
        id: clientsProcess
        command: ["hyprctl", "clients", "-j"]

        stdout: StdioCollector {
            onStreamFinished: {
                const clients = JSON.parse(text);
                const byAddress = {};
                for (const client of clients)
                    byAddress[client.address] = client;
                shell.windowByAddress = byAddress;
            }
        }
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (shell.overviewOpen)
                refreshTimer.restart();
        }
    }

    Timer {
        id: refreshTimer
        interval: 40
        repeat: false
        onTriggered: shell.refresh()
    }

    IpcHandler {
        target: "overview"

        property bool open: shell.overviewOpen
        property bool live: shell.livePreviews

        function toggle() {
            shell.setOpen(!shell.overviewOpen);
        }

        function showOverview() {
            shell.setOpen(true);
        }

        function hideOverview() {
            shell.setOpen(false);
        }

        function useLivePreviews() {
            shell.livePreviews = true;
        }

        function useSnapshots() {
            shell.livePreviews = false;
        }
    }
}
