#!/usr/bin/env python3
"""Check MCP capture JSON from the red/green[/blue] inherited-style Demo fixture.

Usage: python3 scripts/verify-swiftui-palette-capture.py <capture.json> [...]
Each capture contains inspect_node data objects in its top-level details array.
Compare the matching screenshot too: source-path agreement alone is not render proof.
"""
import argparse
import json
import math

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--palette-size', type=int, choices=[2, 3], default=3)
parser.add_argument('captures', nargs='+')
args = parser.parse_args()
for path in args.captures:
    with open(path) as source:
        capture = json.load(source)
    details = {item['node']['text']: item['detail'] for item in capture['details']}
    for level, alpha, channel in [('secondary', .5, 1), ('tertiary', .25, 2 if args.palette_size == 3 else 1)]:
        for mode in ['direct', 'inherit']:
            label = f'HW {mode}-palette-{level}'
            detail = details[label]
            values = {a['semanticPath']: a['value'] for g in detail['attributeGroups']
                      for s in g['sections'] for a in s['attributes']}
            rgba = values['common.text.color']
            assert len(rgba) == 4 and all(math.isfinite(v) and 0 <= v <= 1 for v in rgba), (path, label, rgba)
            assert not detail['semanticContext']['wasTruncated'], (path, label)
            if mode == 'direct':
                # Direct Text attenuates primary red, unlike the inherited palette slots.
                assert rgba[0] > .9 and rgba[0] > max(rgba[1:3]), (path, label, rgba)
                assert math.isclose(rgba[3], alpha, abs_tol=1e-5), (path, label, rgba)
            else:
                assert rgba[channel] > max(rgba[i] for i in range(3) if i != channel), (path, label, rgba)
                assert rgba[3] == 1, (path, label, rgba)
print(f'通过：{len(args.captures)} 份抓取中的直接与继承调色板颜色')
