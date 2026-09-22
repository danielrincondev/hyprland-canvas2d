#!/usr/bin/env python3
"""Test shared rows using real windows and keys in an empty nested Hyprland."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--instance', required=True)
args = parser.parse_args()
instance = next(i for i in json.loads(subprocess.check_output(['hyprctl', 'instances', '-j'])) if i['instance'] == args.instance)
assert args.instance != os.getenv('HYPRLAND_INSTANCE_SIGNATURE'), 'Refusing the live desktop'
env = dict(os.environ, WAYLAND_DISPLAY=instance['wl_socket'], HYPRLAND_INSTANCE_SIGNATURE=args.instance)


def ctl(*command):
    process = subprocess.run(['hyprctl', '-i', args.instance, *command], capture_output=True, text=True, timeout=8)
    assert process.returncode == 0, process.stdout + process.stderr
    result = process.stdout.strip()
    if command[0] in ['eval', 'dispatch', 'reload']:
        assert result == 'ok', result
    return result


def dispatch(action):
    ctl('dispatch', action)
    time.sleep(.2)


def evaluate(code):
    ctl('eval', code)


def keys(*command):
    subprocess.run(['wtype', *command], env=env, check=True, timeout=5)
    time.sleep(.2)


def workspace(number):
    dispatch(f'hl.dsp.focus({{workspace="{number}"}})')


def focus(title):
    dispatch(f'hl.dsp.focus({{window="title:{title}"}})')


def owner(title):
    return next(w for w in json.loads(ctl('clients', '-j')) if w['title'] == title)['workspace']['id']


def shared_count(n):
    evaluate(f'local n=0; for _ in pairs(grid_test.shared.rows) do n=n+1 end; assert(n=={n})')


def shared_keys():
    evaluate('test_keys={}; for _,w in ipairs(hl.get_windows()) do if w.title=="Shared A" or w.title=="Shared B" then test_keys[#test_keys+1]="window:"..tostring(w.stable_id) end end; assert(#test_keys==2)')


assert not json.loads(ctl('clients', '-j')), 'Use an empty test compositor'
assert all(m['name'].startswith(('HEADLESS-', 'WAYLAND-')) for m in json.loads(ctl('monitors', '-j')))
processes = []


def launch(title):
    process = subprocess.Popen(['foot', '--app-id=grid-shared-test', '--title='+title, 'sleep', '600'], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    processes.append(process)
    time.sleep(.4)
    return process


try:
    evaluate('hl.config({input={resolve_binds_by_sym=true}})')
    workspace(5)
    launch('Private 5')
    workspace(1)
    launch('Private 1')
    dispatch('hl.dsp.layout("insert down")')
    first = launch('Shared A')
    dispatch('hl.dsp.layout("insert auto")')
    second = launch('Shared B')
    dispatch('hl.dsp.layout("pan right 217")')
    evaluate('test_pan=grid_test.engine.workspaces["1"].viewport.x')
    shared_keys()
    keys('-M', 'logo', '-M', 'ctrl', '-M', 'shift', 'p', '-m', 'shift', '-m', 'ctrl', '-m', 'logo')
    shared_count(1)
    evaluate('local s=grid_test.engine.workspaces["1"]; assert(s.rows[1].id==s.tiles[test_keys[1]].row_id)')
    workspace(5)
    assert owner('Shared A') == owner('Shared B') == 5
    assert json.loads(ctl('activewindow', '-j'))['title'] == 'Private 5', 'Shared rows must not steal local focus'
    evaluate('local s=grid_test.engine.workspaces["5"]; assert(s.row_views[s.tiles[test_keys[1]].row_id].x==test_pan)')
    evaluate('local s=grid_test.engine.workspaces["5"]; assert(s.rows[1].id==s.tiles[test_keys[1]].row_id)')
    for n in [1, 5, 1, 5]:
        workspace(n)
        assert owner('Shared A') == owner('Shared B') == n
        evaluate('for _,s in pairs(grid_test.engine.workspaces) do assert(grid_test.engine:validate(s)) end')
    workspace(3)  # non-grid layout
    assert owner('Shared A') == 5
    workspace(6)  # empty grid workspace
    assert owner('Shared A') == owner('Shared B') == 6
    assert json.loads(ctl('activewindow', '-j'))['title'] in ['Shared A', 'Shared B']
    focus('Shared B')
    keys('-M', 'logo', 'j', '-m', 'logo')
    evaluate('local s=grid_test.engine.workspaces["6"]; assert(s.empty_row.selected and not s.focus_key); assert(not hl.get_active_window())')
    keys('typing-in-empty-row')
    keys('-M', 'logo', 'k', '-m', 'logo')
    assert json.loads(ctl('activewindow', '-j'))['title'] == 'Shared B'
    keys('-M', 'logo', '-k', 'Tab', '-m', 'logo')
    keys('-k', 'Down')
    evaluate('assert(grid_test.engine.workspaces["6"].empty_row.selected); assert(not hl.get_active_window())')
    assert ctl('submap') == 'scrolloverview'
    keys('-k', 'Return')
    assert ctl('submap') == 'default'
    evaluate('assert(not hl.get_active_window())')
    local = launch('New local row')
    evaluate('local s=grid_test.engine.workspaces["6"]; assert(not s.empty_row); local id=s.tiles[s.focus_key].row_id; for _,r in pairs(grid_test.shared.rows) do assert(r.row_id~=id or r.workspace_id~="6") end')
    local.terminate()
    local.wait(timeout=5)
    time.sleep(.3)
    evaluate('assert(grid_test.engine.workspaces["6"].empty_row)')
    focus('Shared B')
    dispatch('hl.dsp.layout("share on 1,5,6")')
    workspace(7)
    assert owner('Shared A') == 6, 'Explicit sharing scope must be respected'
    workspace(1)
    assert owner('Shared A') == 1
    # Reload twice: the plugin may itself trigger a second configuration pass.
    for _ in range(2):
        ctl('reload')
        time.sleep(.6)
        assert not ctl('configerrors')
        shared_count(1)
    shared_keys()
    workspace(5)
    assert owner('Shared A') == owner('Shared B') == 5, 'Sharing must survive configuration reload'
    evaluate('hl.config({input={resolve_binds_by_sym=true}})')
    focus('Shared B')
    keys('-M', 'logo', '-k', 'Tab', '-m', 'logo')
    assert ctl('submap') == 'scrolloverview'
    keys('-M', 'logo', '1', '-m', 'logo')
    assert owner('Shared A') == owner('Shared B') == 1
    assert ctl('submap') == 'scrolloverview', 'Shared transfer must keep overview open'
    focus('Shared B')
    keys('-M', 'logo', '-M', 'ctrl', '-M', 'shift', 'p', '-m', 'shift', '-m', 'ctrl', '-m', 'logo')
    shared_count(0)
    keys('-M', 'logo', '5', '-m', 'logo')
    assert owner('Shared A') == 1, 'Unshared row must stay in its workspace'
    keys('-k', 'Escape')
    workspace(1)
    focus('Shared B')
    dispatch('hl.dsp.layout("share on")')
    first.terminate()
    first.wait(timeout=5)
    time.sleep(.3)
    workspace(5)
    assert owner('Shared B') == 5
    second.terminate()
    second.wait(timeout=5)
    time.sleep(.3)
    shared_count(0)
    assert not ctl('configerrors')
    print('PASS: real shared-row shortcut, ownership, focus, pan, scopes, empty workspaces, reload, overview and closure')
finally:
    ctl('dispatch', 'hl.plugin.scrolloverview.overview("close")')
    for process in processes:
        if process.poll() is None:
            process.terminate()
    for process in processes:
        process.wait(timeout=5)
