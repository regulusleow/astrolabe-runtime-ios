# Astrolabe iOS Runtime Validation Report

> Historical scope: this report records V1 validation against Wire Protocol
> 1.0. The planned platform-neutral refactor and Wire Protocol 2.0 belong to V2
> and do not change the results recorded here.

## 1. Purpose

This report records the end-to-end validation performed on 2026-07-11 for
Astrolabe iOS Runtime. The goal was to determine whether the runtime is usable
for AI-assisted iOS UI inspection and whether it satisfies the V1 acceptance
criteria defined in [ios-runtime-strategy.md](./ios-runtime-strategy.md).

## 2. Conclusion

The simulator runtime path is usable for real UI inspection. Astrolabe can
discover a Debug application, capture its UIKit and CALayer hierarchy, inspect
node details, calculate layout relationships, validate styles, capture a
host-side screenshot, and perform a pixel comparison through MCP.

The P0 runtime path is complete. The Host discovers the project-owned Runtime
through simulator TCP and paired USB devices, negotiates the wire protocol
before App data is exposed, and reports handshake failures as endpoint
diagnostics. The project-owned iOS Runtime provider is now the only production
provider. The Runtime also exposes a discoverable allowlist for temporary,
in-memory presentation-attribute patches.

## 3. Test Scope

The validation covered three repositories:

| Component | Repository | Responsibility |
| --- | --- | --- |
| Wire protocol | `astrolabe-protocol` | Frame codec, request/response contract, DTOs, Schemas and Fixtures |
| iOS Runtime SDK | `astrolabe-runtime-ios` | UIKit inspection, local transport and lifecycle |
| Host and MCP | `astrolabe` | Runtime discovery, protocol client, CLI checks, screenshots and MCP tools |
| Demo application | `lookinMCPTest` | Real UIKit process used for Debug and Release integration tests |

## 4. Automated Results

| Test | Result | Notes |
| --- | --- | --- |
| Protocol package tests | 22/22 passed | Codec, DTO round trips, Schemas and Fixtures |
| Runtime SDK tests on macOS | 20/20 passed | Transport, server and module-boundary tests |
| Runtime SDK tests on iOS Simulator | 39/39 passed | Includes UIKit containers, multiple windows and SwiftUI hosting |
| Astrolabe Host tests | 100/100 passed | Includes USB discovery and handshake diagnostics |
| Astrolabe Host Release build | Passed | Host package builds successfully in Release configuration |
| Demo Debug build and cold start | Passed | Runtime endpoint was rediscovered with a new process identifier |
| Demo Release build | Passed | Generic iOS Release configuration builds successfully |
| MCP smoke test | Passed | 22 tools were loaded and the Runtime inspection and patch workflows completed |
| Screenshot and baseline comparison | Passed | 1170 x 2532 device screenshots; identical baseline mismatch ratio was 0 |
| USB smoke test | Passed | 71 nodes; CLI and MCP hierarchy, detail, screenshot and baseline paths completed |

Strict concurrency checking produced warnings only in SDK XCTest code where
`XCTestCase` is captured by `MainActor.run`. Runtime production sources passed
the same check without warnings. These test warnings will become errors under
Swift 6 language mode and should be removed before enabling that mode.

## 5. Runtime Workflow Validation

The following paths were exercised against a running Demo application:

1. Discover a simulator endpoint and complete the protocol handshake.
2. Read application, process, screen and device metadata.
3. Capture the active UIKit and CALayer hierarchy.
4. Find nodes by class, text and runtime properties.
5. Read full node details and summarized semantic attributes.
6. Validate node properties with `check_node` and `check_node_detail`.
7. Measure node relationships with `check_layout`.
8. Validate font and color properties with `check_style`.
9. Capture a host-side simulator screenshot.
10. Record a baseline and run a pixel comparison.
11. Reject a stale application identifier after the inspected process restarts.
12. Discover the Runtime-owned temporary patch allowlist.
13. Apply, read back, list, revert, and clear temporary UI attribute patches.

The stale-process test returned the stable error code
`astrolabe_runtime_stale_app` and identified the replacement process, allowing
the caller to recover by discovering applications again.

## 6. LookinServer Cross-validation

The Demo application exposed both LookinServer and Astrolabe Runtime during the
comparison. The two providers inspected the same process and screen.

| Comparison | Result |
| --- | --- |
| Screen geometry | Both reported 440 x 956 points at scale 3 |
| UIView node count | Both reported 35 view nodes |
| UIView class distribution | Exact match across all 35 nodes |
| Preview frame | Both reported `(91, 137, 258, 559)` |
| Save button frame | Both reported `(70, 872, 300, 50)` |
| Navigation title font | Both reported `.SFUI-Bold`, 17 pt |
| Navigation title color | Both reported `#141C2F` |
| Screen background | Both reported `#FFFFFF` |

Astrolabe additionally exposes CALayer nodes as independent hierarchy nodes, so
its complete snapshot contained 70 nodes: 35 views and 35 layers. Astrolabe's
hierarchy frame uses screen coordinates, while node details also retain parent
and screen coordinate forms. This is suitable for screenshot-based layout
verification.

Astrolabe also exposed visible text nodes that were absent from the tested
Lookin hierarchy response, including the navigation title, chat labels and Save
button title.

## 7. V1 Acceptance Status

| Acceptance criterion | Status | Evidence or gap |
| --- | --- | --- |
| Simulator discovery across restarts | Passed | Fresh process is discovered and stale identifiers are rejected |
| USB runtime discovery | Passed | Host discovered and inspected the project-owned Runtime through usbmux |
| UIKit and CALayer hierarchy | Passed for tested screen | Node count, classes and key frames matched LookinServer |
| V1 semantic node details | Passed for tested screens | Text, typography, colors, geometry, visibility, border, corner, shadow, control state and Auto Layout semantics are available; visibility coverage includes screen and scroll-viewport intersection |
| Existing CLI and MCP commands | Passed | No command-layer changes were required during the smoke test |
| Host-side screenshot and visual diff | Passed | Native-resolution simulator screenshot and baseline comparison succeeded |
| Runtime path independent of Lookin models | Passed | New protocol path does not require Lookin archives or shared models |
| Controlled mutation contract | Passed | Only Runtime-advertised temporary presentation attributes can be patched; arbitrary invocation and persistent mutation are unavailable |
| Legacy Lookin path removed from Host | Passed | Production registration contains only `AstrolabeIOSRuntimeProvider` |

## 8. V1 Closure Work

### 8.1 USB transport

Completed. The Host isolates usbmux behind an Astrolabe byte-stream adapter,
scans the project-owned device port range, and routes typed protocol frames
through the same client used by simulator TCP.

### 8.2 Semantic attribute coverage

The Runtime emits separate `shadowOffsetWidth` and `shadowOffsetHeight`
semantics in addition to the structured `shadowOffset` value. Colors use
standard sRGB with each channel normalized to the `0...1` range, and
`tintAdjustmentMode` is available as a typed view attribute.

`imageName` is only appropriate when UIKit exposes a reliable public resource
identifier. Native-resolution host screenshots replace a protocol-level image
preview, and Lookin-specific `outsideEdge` metadata is not part of the
Astrolabe V1 contract.

### 8.3 Lifecycle integration

Completed. `ASTRuntime` provides Swift and Objective-C entry points that
serialize lifecycle transitions on the main actor. Integrations start from
`sceneDidBecomeActive` and stop from `sceneDidEnterBackground`.

### 8.4 Validation matrix

The automated matrix now covers `UIScrollView`, `UITableView`,
`UICollectionView`, text inputs, image views, button states, Auto Layout,
multiple window sizes, multiple foreground-scene window aggregation, and
SwiftUI hosting hierarchies. Visibility regression coverage distinguishes
screen-offscreen nodes, scroll-clipped nodes, and partially visible nodes. The
physical-device smoke path covers discovery, hierarchy, node detail,
native-resolution screenshots, baseline comparison, CLI and MCP.

### 8.5 Migration cleanup

Completed. Host production registration uses only the project-owned iOS
Runtime provider. The legacy Lookin provider, archive decoder, shared models
and vendor sources are no longer part of the production Runtime path.

### 8.6 Documentation and Swift 6 readiness

SPM integration, Objective-C bridging, Debug-only startup, lifecycle behavior,
and temporary attribute patches are documented in the package README. Remove
the strict-concurrency warnings from the test suite before enabling Swift 6
language mode.

## 9. Readiness Decision

Astrolabe iOS Runtime is ready for simulator and USB development and UI
verification. Runtime and Host consume `AstrolabeProtocol 1.0.0` over Wire
Protocol 2.0, and temporary patches remain bounded by the Runtime-owned
allowlist. Swift 6 test readiness, broader semantic cross-validation, and
real-project soak testing remain follow-up work.
