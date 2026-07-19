# Astrolabe Runtime for iOS

Astrolabe Runtime for iOS exposes UIKit and Core Animation inspection data to
the Astrolabe Host during development. Runtime activation is compiled out of
Release builds.

Current package release: `1.0.0`.

## Requirements

- iOS 15 or later
- Xcode with Swift 5.9 or later
- Astrolabe Host tools

## Installation

Add the following package in Xcode:

```text
https://github.com/regulusleow/astrolabe-runtime-ios
```

Link the `AstrolabeRuntime` product to the application target.

## Integration

Start and stop the Runtime from the active scene lifecycle.

Objective-C:

```objc
@import AstrolabeRuntime;

- (void)sceneDidBecomeActive:(UIScene *)scene {
#if DEBUG
    [ASTRuntime start];
#endif
}

- (void)sceneDidEnterBackground:(UIScene *)scene {
#if DEBUG
    [ASTRuntime stop];
#endif
}
```

Swift:

```swift
func sceneDidBecomeActive(_ scene: UIScene) {
#if DEBUG
    ASTRuntime.start()
#endif
}

func sceneDidEnterBackground(_ scene: UIScene) {
#if DEBUG
    ASTRuntime.stop()
#endif
}
```

Use `startWithCompletion:` when Objective-C code needs to handle startup
failures. `UIKitRuntimeLifecycle` is available for custom port selection,
request limits, or inspection authorization.

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
| `AstrolabeRuntimeCore` | Protocol server, routing, sessions, transport, node registry, and platform-independent patch coordination used by the iOS SDK. |
| `AstrolabeRuntimeUIKit` | UIKit and Core Animation collection, attribute mapping, Auto Layout, accessibility, and allowlisted mutations. |
| `AstrolabeRuntime` | Public `ASTRuntime` facade, SDK metadata, lifecycle, and dependency composition. |
| `AstrolabeRuntimeObjC` | Minimal Objective-C Runtime metadata adapter. |

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
```

Run UIKit and integration tests in an iOS Simulator:

```bash
xcodebuild \
  -scheme astrolabe-runtime-ios \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest' \
  test
```

## Security

The Runtime listens only on a loopback TCP endpoint and is unavailable in
Release builds. USB transport also relies on host-device pairing enforced by
usbmux. Do not distribute Debug builds containing sensitive runtime data.

Temporary mutation is restricted to the Runtime-owned patch catalog. Arbitrary
selectors, method invocation, and business actions are not exposed.

## License

Astrolabe Runtime for iOS is available under the
[Apache License 2.0](LICENSE).
