#!/usr/bin/env python3
"""Check real MCP captures from the List/LazyVStack and UIKit regression fixtures."""

import argparse
import json
from pathlib import Path


def attributes(envelope):
    return {
        item["semanticPath"]: item["value"]
        for group in envelope["data"]["detail"]["attributeGroups"]
        for section in group["sections"]
        for item in section["attributes"]
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture_directory", type=Path)
    args = parser.parse_args()
    surfaces = json.loads((args.capture_directory / "surfaces-evidence.json").read_text())
    for surface, size in [("list", 18), ("lazy", 19)]:
        for revision in [0, 1]:
            key = f"{surface}-{revision}-detail"
            envelope = surfaces[key]
            values = attributes(envelope)
            assert values["common.text.fontName"], key
            assert values["common.text.fontSize"]["value"] == size, key
            red, green, blue, alpha = values["common.text.color"]
            assert alpha == 1, key
            assert (blue > red and blue > green) if surface == "list" else (red > green and blue > green), key
            issues = envelope["data"]["detail"]["semanticContext"]["issues"]
            assert not any(item["code"].endswith("ambiguousTextScope") for item in issues), key

    controls = json.loads((args.capture_directory / "uikit-evidence.json").read_text())
    assert [item["revision"] for item in controls] == [0, 1], "缺少开关的两个状态"
    for item in controls:
        values = attributes(item["details"]["toggle"])
        assert values["ios.control.isOn"] is (item["revision"] == 1), "开关状态不匹配"
    print("通过：列表字体与颜色、UISwitch 开关状态")


if __name__ == "__main__":
    main()
