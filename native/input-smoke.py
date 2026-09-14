#!/usr/bin/env python3
"""Exercise real key events in an EMPTY nested compositor, never the live desktop."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--instance", required=True)
args = parser.parse_args()
instances = json.loads(subprocess.check_output(["hyprctl", "instances", "-j"]))
instance = next(i for i in instances if i["instance"] == args.instance)
assert args.instance != os.getenv("HYPRLAND_INSTANCE_SIGNATURE"), "Refusing the current desktop"
env = dict(os.environ, WAYLAND_DISPLAY=instance["wl_socket"], HYPRLAND_INSTANCE_SIGNATURE=args.instance)


def ctl(*command):
    result = subprocess.run(["hyprctl", "-i", args.instance, *command], capture_output=True, text=True, check=True, timeout=8)
    assert not result.stdout.startswith("error"), result.stdout
    return result.stdout


def keys(*command):
    subprocess.run(["wtype", *command], env=env, check=True, timeout=5)
    time.sleep(0.2)


def active():
    return json.loads(ctl("activewindow", "-j"))


assert not json.loads(ctl("clients", "-j")), "Use an empty test compositor"
assert all(m["name"].startswith(("HEADLESS-", "WAYLAND-")) for m in json.loads(ctl("monitors", "-j")))
# wtype supplies a synthetic keymap; resolve its keysyms, not physical US keycodes.
ctl("eval", 'hl.config({input={resolve_binds_by_sym=true}})')
ctl("dispatch", 'hl.dsp.focus({workspace="1"})')
processes = []
with tempfile.TemporaryDirectory(prefix="grid-key-test-") as directory:
    root = Path(directory)
    reader = 'import os,sys,tty; tty.setraw(0); f=open(sys.argv[1],"ab",buffering=0)\nwhile True: f.write(os.read(0,1024))'
    logs = [root / f"keys-{n}" for n in range(6)]
    try:
        for n, log in enumerate(logs):
            log.touch()
            processes.append(subprocess.Popen(["foot", "--app-id=grid-input-test", f"--title=Input test {n}", "python3", "-c", reader, str(log)], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
            time.sleep(0.35)
        for n in range(3, 6):
            ctl("dispatch", f'hl.dsp.focus({{window="title:Input test {n}"}})')
            ctl("dispatch", 'hl.dsp.layout("move down")')
            time.sleep(0.2)
        # A populated neighboring workspace makes accidental edge traversal
        # observable instead of silently staying on the only workspace.
        ctl("dispatch", 'hl.dsp.focus({workspace="2"})')
        neighbor_log = root / "neighbor-keys"
        neighbor_log.touch()
        processes.append(subprocess.Popen(["foot", "--app-id=grid-input-test", "--title=Neighbor workspace", "python3", "-c", reader, str(neighbor_log)], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
        time.sleep(0.4)
        logs.append(neighbor_log)
        ctl("dispatch", 'hl.dsp.focus({workspace="1"})')
        ctl("dispatch", 'hl.dsp.focus({window="title:Input test 5"})')
        keys("z")
        assert b"".join(p.read_bytes() for p in logs) == b"z", "Input probe must work before overview"
        for log in logs:
            log.write_bytes(b"")
        keys("-M", "logo", "-k", "Tab", "-m", "logo")
        assert ctl("submap").strip() == "scrolloverview", "Shortcut must enter overview input mode"
        before = active()["address"]
        keys("-k", "Left")
        assert active()["address"] != before, "Arrow must select another window"
        keys("k")
        assert active()["title"] in ["Input test 0", "Input test 1", "Input test 2"], "K must select the upper row"
        moving = active()
        ctl("eval", 'grid_test_moving_key = require("grid").setup().engine.workspaces["1"].focus_key')
        tile = 'require("grid").setup().engine.workspaces["1"].tiles[grid_test_moving_key]'
        ctl("eval", "grid_test_original_row = " + tile + ".row_id")
        keys("-M", "logo", "-M", "shift", "-k", "Down", "-m", "shift", "-m", "logo")
        assert active()["address"] == moving["address"], "Move shortcut must not also navigate"
        ctl("eval", "assert(" + tile + ".row_id ~= grid_test_original_row)")
        keys("-M", "logo", "-M", "shift", "-k", "Up", "-m", "shift", "-m", "logo")
        ctl("eval", "assert(" + tile + ".row_id == grid_test_original_row)")
        for number in [2, 1]:
            keys("-M", "logo", str(number), "-m", "logo")
            assert active()["workspace"]["id"] == number, "Super+number must switch workspace"
            assert ctl("submap").strip() == "scrolloverview", "Workspace shortcut must keep overview open"
        keys("-M", "logo", "0", "-m", "logo")
        assert json.loads(ctl("activeworkspace", "-j"))["id"] == 10
        assert ctl("submap").strip() == "scrolloverview", "Empty workspace must keep overview active"
        keys("-M", "logo", "1", "-m", "logo")
        keys("-M", "logo", "-k", "Right", "-m", "logo")
        for direction in ["Left", "Right", "Up", "Down"]:
            for _ in range(7):
                keys("-k", direction)
                assert active()["workspace"]["id"] == 1, "Window navigation crossed into another workspace"
        keys("abc123")
        keys("-M", "ctrl", "a", "-m", "ctrl")
        assert not any(p.read_bytes() for p in logs), "Overview leaked typing or navigation into a client"
        selected = active()["address"]
        keys("-k", "Return")
        assert ctl("submap").strip() == "default", "Enter must leave overview input mode: " + ctl("submap")
        assert active()["address"] == selected
        assert not any(p.read_bytes() for p in logs), "Enter must not reach the selected client"
        keys("z")
        assert b"".join(p.read_bytes() for p in logs) == b"z", "Application input must resume after overview"
        for close in [("-k", "Escape"), ("-M", "logo", "-k", "Tab", "-m", "logo")]:
            keys("-M", "logo", "-k", "Tab", "-m", "logo")
            keys(*close)
            assert ctl("submap").strip() == "default"
        assert not ctl("configerrors").strip()
        print("PASS: overview shortcuts, window movement, numbered workspaces, workspace boundaries, typing suppression, and restored client input")
    finally:
        ctl("dispatch", 'hl.plugin.scrolloverview.overview("close")')
        for process in processes:
            process.terminate()
        for process in processes:
            process.wait(timeout=5)
