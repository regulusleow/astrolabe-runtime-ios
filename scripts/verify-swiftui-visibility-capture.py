#!/usr/bin/env python3
"""Assert saved MCP results from VisibilityRegressionPage and the List/Lazy Demo.

Usage: python3 scripts/verify-swiftui-visibility-capture.py <capture-directory>
Capture each state while the app runs in the foreground. Files contain the
inspect_screen, find_nodes, and visibleOnly results as screen/nodes/visible.
frozen-vis-0.json is a repeat find_nodes for revision 0 after switching to 1.
"""
import json
import math
import sys
from pathlib import Path

root = Path(sys.argv[1])


def load(name):
    return json.loads((root / name).read_text())


def nodes(capture):
    return capture['nodes']['data']['nodes']


def check_filter(capture):
    expected = {n['oid'] for n in nodes(capture) if n.get('visible') is True}
    actual = {n['oid'] for n in capture['visible']['data']['nodes']}
    assert actual == expected, (expected, actual)
    for node in nodes(capture):
        if 'visible' not in node:
            continue
        assert node['kind'] == 'semantic'
        alpha = node['effectiveAlpha']
        assert math.isfinite(alpha) and 0 <= alpha <= 1
        hierarchy = not node['hidden'] and not node['inHiddenHierarchy'] and alpha > .01
        assert node['hierarchyVisible'] == hierarchy
        assert node['visible'] == (hierarchy and node['intersectsViewport'] and not node['fullyClippedByAncestor'])


before, after = (load(f'runtime-vis-{revision}.json') for revision in (0, 1))
for capture in (before, after):
    check_filter(capture)
initial = {n['text']: n for n in nodes(before)}
updated = {n['text']: n for n in nodes(after)}
for label in ('Normal', 'Covered', 'Noninteractive'):
    assert initial['VIS ' + label]['visible'] is True, label
for label in ('Boundary', 'Nested opacity', 'Opacity low', 'Parent opacity', 'Offscreen', 'Clipped'):
    assert initial['VIS ' + label]['visible'] is False, label
assert initial['VIS Clipped']['intersectsViewport'] is True
assert initial['VIS Clipped']['fullyClippedByAncestor'] is True
assert initial['VIS Offscreen']['intersectsViewport'] is False
assert 'VIS Hidden' not in initial and 'VIS Opacity zero' not in initial
assert len(updated) == 10 and all(n['visible'] for n in updated.values())
assert load('frozen-vis-0.json')['data']['nodes'] == nodes(before)

for surface in ('list', 'lazy'):
    for revision in (0, 1):
        capture = load(f'surface-{surface}-{revision}.json')
        check_filter(capture)
        rows = nodes(capture)
        assert rows and all('visible' in n for n in rows), (surface, revision)
        label = f'REG {surface.title()} row {0 if revision == 0 else 30} rev {revision}'
        assert any(n['text'] == label and n['visible'] for n in rows), label
        assert any(not n['visible'] for n in rows), (surface, revision)
        assert all(n['text'].endswith(f'rev {revision}') for n in rows)

unsupported = load('unsupported.json')
check_filter(unsupported)
assert nodes(unsupported) and all('visible' not in n for n in nodes(unsupported))
private = load('privacy.json')
assert nodes(private) and all('visible' not in n for n in nodes(private) if n['className'] == 'SwiftUI.AccessibilityNode')
assert 'HW_SECRET_9D28' not in json.dumps(private)
print('通过：基础可见性、过滤、快照冻结、List/Lazy 滚动、未知裁剪、隐私门')
