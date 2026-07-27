#!/usr/bin/env bash

set -euo pipefail

select_runtime() {
  xcrun simctl list runtimes --json | python3 -c '
import json
import re
import sys

runtimes = [
    runtime
    for runtime in json.load(sys.stdin).get("runtimes", [])
    if runtime.get("isAvailable")
    and runtime.get("identifier", "").startswith(
        "com.apple.CoreSimulator.SimRuntime.iOS-"
    )
]
if runtimes:
    latest = max(
        runtimes,
        key=lambda runtime: tuple(
            int(component)
            for component in re.findall(r"\d+", runtime.get("version", "0"))
        ),
    )
    print(latest["identifier"])
'
}

select_device_type() {
  xcrun simctl list devicetypes --json | python3 -c '
import json
import sys

device_types = [
    device_type
    for device_type in json.load(sys.stdin).get("devicetypes", [])
    if device_type.get("name", "").startswith("iPhone")
]
preferred = next(
    (
        device_type
        for device_type in device_types
        if device_type.get("name") == "iPhone 16 Pro"
    ),
    None,
)
selected = preferred or (device_types[0] if device_types else None)
if selected:
    print(selected["identifier"])
'
}

runtime_identifier="$(select_runtime)"
if [[ -z "$runtime_identifier" ]]; then
  xcodebuild -downloadPlatform iOS
  runtime_identifier="$(select_runtime)"
fi

device_type_identifier="$(select_device_type)"
if [[ -z "$runtime_identifier" || -z "$device_type_identifier" ]]; then
  printf 'Unable to resolve an available iOS Simulator runtime and device type\n' >&2
  exit 1
fi

device_udid="$(
  xcrun simctl create \
    Astrolabe-CI \
    "$device_type_identifier" \
    "$runtime_identifier"
)"

cleanup() {
  xcrun simctl delete "$device_udid" >/dev/null 2>&1 || true
}
trap cleanup EXIT

xcodebuild \
  -scheme astrolabe-runtime-ios \
  -destination "platform=iOS Simulator,id=${device_udid}" \
  test
