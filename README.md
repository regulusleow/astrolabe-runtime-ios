# Astrolabe Runtime for iOS

English | [简体中文](README.zh-CN.md)

Astrolabe Runtime for iOS exposes UIKit and Core Animation inspection data to
the Astrolabe Host during development. Linking the dynamic framework is the
complete integration: the Runtime starts automatically when an eligible
application process loads it.

Current package release: `2.1.0`.

## Requirements

- iOS 15 or later
- Xcode with Swift 5.9 or later
- Astrolabe Host tools

## Installation

Add the following package in Xcode:

```text
https://github.com/regulusleow/astrolabe-runtime-ios
```

Link and embed the `AstrolabeRuntime` product only in application targets that
are allowed to expose runtime inspection data, such as Debug and internal Beta
targets. Existing integrations upgraded from the former static product must
verify that the framework is configured as `Embed & Sign`.

## Integration

No source integration is required. Do not import the module or add
`AppDelegate` or `SceneDelegate` lifecycle calls. The dynamic framework
installs its process-level lifecycle observer when it is loaded, starts after
application launch, and keeps the same Runtime instance across foreground and
background transitions.

The Runtime does not inspect `DEBUG` or application configuration names.
Linking and embedding the product enables it in any build configuration.
Release and App Store targets must therefore remove `AstrolabeRuntime` from
their dependency graph and final application bundle. Treat a final artifact
scan as a required release gate.

## Capabilities

- Simulator and paired USB Runtime discovery.
- UIKit and Core Animation hierarchy collection.
- Frames, visibility, accessibility, text, typography, colors, borders,
  shadows, control state, images, and Auto Layout metadata.
- Node-detail lookup through stable opaque identifiers.
- Allowlisted, in-memory presentation patches for supported text, font, color,
  alpha, border, corner, shadow, and identified Auto Layout constraint values.

Patches never modify source code, the App binary, application models, or
persistent storage. They remain active across Host reconnections and are
discarded when the Runtime stops or the App process exits.

## Architecture

| Target | Responsibility |
| --- | --- |
| `AstrolabeRuntimeCore` | Protocol server, routing, sessions, transport, node registry, and platform-independent patch coordination. |
| `AstrolabeRuntimeUIKit` | UIKit and Core Animation collection, attributes, layout, accessibility, and allowlisted mutations. |
| `AstrolabeRuntime` | Automatic installer, process lifecycle coordination, SDK metadata, and dependency composition. |
| `AstrolabeRuntimeBootstrap` | Objective-C dynamic-framework load hook with no public lifecycle API. |
| `AstrolabeRuntimeObjC` | Objective-C Runtime metadata adapter used by UIKit collection. |

The package implements the platform-neutral Wire Protocol from
`astrolabe-protocol`. iOS-specific collection, mapping, lifecycle, and port
selection remain inside this repository.

## Development

Run the macOS-compatible tests and Release build:

```bash
npm ci
npm test
swift test --parallel
swift build -c release --product AstrolabeRuntime
scripts/verify-auto-start-artifact.sh
```

Run UIKit and integration tests in an iOS Simulator:

```bash
xcodebuild \
  -scheme astrolabe-runtime-ios \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest' \
  test
```

## Security

The Runtime listens only on a loopback TCP endpoint. USB transport also relies
on host-device pairing enforced by usbmux. The Runtime has no internal build
configuration gate: if its framework is present in a Release build, it will
start automatically. Do not distribute builds containing the Runtime or
sensitive runtime data.

Temporary mutation is restricted to the Runtime-owned patch catalog. Arbitrary
selectors, method invocation, and business actions are not exposed.

## License

Astrolabe Runtime for iOS is available under the
[Apache License 2.0](LICENSE).
