# Astrolabe iOS Runtime Strategy

## 1. Decision

Astrolabe will not rewrite LookinServer feature by feature. It implements a
project-owned `AstrolabeRuntime` SDK containing the inspection capabilities and
allowlisted temporary presentation-attribute patches required by AI UI
verification.

The implementation will be Swift-first rather than pure Swift. The independent
`AstrolabeProtocol` package owns the wire DTOs and codecs. Swift code in this
SDK owns request routing, concurrency, hierarchy collection, and typed
attribute collectors. Objective-C is restricted to a thin adapter layer for
PeerTalk and Objective-C Runtime operations that are materially clearer or
safer outside Swift.

The new runtime will use an Astrolabe protocol. It will not emulate the Lookin
archive format or maintain compatibility with Lookin request and model types.

## 2. Original Dependency Surface

The original Host implementation used four Lookin request types:

| Request | Current purpose | Astrolabe replacement |
| --- | --- | --- |
| `Ping` | Validate server version and connection state | Capability handshake |
| `App` | Read App and device metadata | `RuntimeAppInfo` |
| `Hierarchy` | Read the UIView/CALayer hierarchy | `RuntimeHierarchySnapshot` |
| `AllAttrGroups` | Read details for one runtime node | `RuntimeNodeDetail` |

High-fidelity screenshots already come from host-side `simctl` or `devicectl`.
The runtime SDK therefore does not need to transfer screenshots in its initial
scope. A low-resolution runtime preview can be added later as an optional
capability if a real fallback requirement is demonstrated.

## 3. Scope

### 3.1 Required

- Debug-only startup and shutdown.
- Local simulator endpoint and USB-forwarded transport availability.
- Protocol version and capability handshake.
- App, process, screen, and device metadata.
- Active UIWindow discovery.
- UIView and CALayer hierarchy snapshots.
- Session-scoped stable node identifiers.
- Common frame, bounds, visibility, alpha, class chain, color, and hierarchy
  metadata.
- Typed details for UIKit controls used by UI verification.
- Auto Layout and accessibility metadata.
- Stable errors, request cancellation, timeout, and payload-size limits.

### 3.2 Explicitly Excluded

- Unrestricted Runtime property modification outside the advertised patch catalog.
- Custom setter invocation.
- Arbitrary selector enumeration or method invocation.
- Gesture recognizer modification.
- Desktop-client export features.
- Lookin archive/model compatibility.
- Full SwiftUI private state or modifier introspection.
- Production or release-build activation.

SwiftUI screens remain inspectable through their UIKit hosting hierarchy,
accessibility information, and screenshots. Support for private SwiftUI
internals is not part of the contract.

## 4. Architecture

```text
astrolabe-protocol
└── AstrolabeProtocol
    ├── Frame and message codecs
    ├── Request and response envelopes
    ├── Handshake and version negotiation
    └── Platform-neutral DTOs and errors

astrolabe-runtime-ios
└── AstrolabeRuntime
    ├── RuntimeServer
    │   ├── RequestRouter
    │   ├── CapabilityHandshake
    │   ├── RequestContext
    │   └── TransportAdapter
    ├── SnapshotService
    │   ├── WindowProvider
    │   ├── HierarchyCollector
    │   ├── NodeRegistry
    │   └── AttributeCollectorRegistry
    ├── AttributeCollectors
    │   ├── UIViewCollector
    │   ├── CALayerCollector
    │   ├── UILabelCollector
    │   ├── UIImageViewCollector
    │   ├── UIControlCollector
    │   ├── TextInputCollector
    │   ├── UIScrollViewCollector
    │   ├── UIStackViewCollector
    │   ├── AutoLayoutCollector
    │   └── AccessibilityCollector
    └── ObjectiveCAdapters
        ├── PeerTalkTransportAdapter
        └── RuntimeMetadataAdapter
```

### 4.1 Responsibility Boundaries

| Component | Responsibility |
| --- | --- |
| `TransportAdapter` | Move framed bytes without understanding UI requests |
| `RequestRouter` | Validate and dispatch protocol methods |
| `SnapshotService` | Coordinate main-thread runtime inspection |
| `HierarchyCollector` | Build the recursive node tree |
| `NodeRegistry` | Map session node IDs to weak runtime objects |
| `AttributeCollectorRegistry` | Select collectors by runtime object type |
| Attribute collectors | Read one coherent category of typed properties |
| `AstrolabeProtocol` | Define and encode the platform-neutral wire contract |

Transport, UIKit inspection, serialization, and AI-facing normalization must
remain separate. A transport replacement must not affect hierarchy collectors,
and adding a UIKit collector must not modify request routing.

Host-side endpoint discovery remains the responsibility of
`AstrolabeIOSRuntimeProvider` and its transport adapters. The App-side SDK only
starts supported endpoints and responds to protocol requests.

### 4.2 V2 SwiftPM Target Boundaries

V1 keeps Core, Network transport, UIKit inspection, patching, and the public
facade in one Swift target. UIKit files are conditionally compiled, which makes
the module expose different symbols on macOS and iOS and prevents SwiftPM from
enforcing the intended dependency direction. V2 will preserve one repository
and one public library product while splitting implementation ownership:

```text
AstrolabeRuntime product
└── AstrolabeRuntime                  Public facade and composition root
    ├── AstrolabeRuntimeCore          Server, sessions, routing, transport
    └── AstrolabeRuntimeUIKit         UIKit inspection and mutation
        ├── AstrolabeRuntimeCore
        └── AstrolabeRuntimeObjC      Runtime metadata adapter

AstrolabeRuntimeCore ───────────────▶ AstrolabeProtocol 2.0
AstrolabeRuntimeUIKit ──────────────▶ AstrolabeProtocol 2.0
```

| Target | Owned types and behavior |
| --- | --- |
| `AstrolabeRuntimeCore` | `RuntimeServer`, request routing and execution, connection sessions, transport contracts, local TCP transport, configuration, node registry, inspection service contracts, and generic patch coordination. |
| `AstrolabeRuntimeUIKit` | Scene/window discovery, hierarchy and detail providers, collectors, UIKit-to-Protocol mapping, color/accessibility mapping, Auto Layout, patch catalog, mutator, and inspection service factory. |
| `AstrolabeRuntime` | `ASTRuntime`, SDK version metadata, supported configuration, lifecycle state, and construction of the complete iOS Runtime graph. |
| `AstrolabeRuntimeObjC` | Objective-C Runtime operations that cannot be represented as clearly or safely in Swift. |

The split follows these rules:

- Cross-target implementation APIs use Swift `package` access instead of
  becoming public SDK surface merely to satisfy module visibility.
- The public product keeps the `AstrolabeRuntime` module and exposes only the
  integration facade and intentionally supported configuration.
- `AstrolabeRuntimeCore` is an internal boundary for this iOS repository. It is
  not a new shared repository and is not reused by the Kotlin Android Runtime.
- A separate transport target is deferred until a second App-side transport
  implementation creates a real independent evolution need.
- UIKit source files no longer rely on `#if canImport(UIKit)` to simulate a
  module boundary; target platform declarations and dependencies enforce it.
- Core, UIKit, facade, and Objective-C integration tests belong to separate test
  targets so macOS Core validation cannot be mistaken for iOS Runtime coverage.

## 5. Language Boundary

### 5.1 Swift

- Codable protocol and data models.
- Async request lifecycle and cancellation.
- Capability negotiation.
- UIKit/CALayer traversal through public APIs.
- Main-actor snapshot coordination.
- Attribute collector strategies and registry.
- Error mapping and test fixtures.

### 5.2 Objective-C

- Existing PeerTalk integration while USB transport still depends on it.
- Small Objective-C Runtime helpers when class, ivar, or associated-object
  operations cannot be represented clearly in Swift.

Objective-C code must return typed values to Swift. It must not own request
routing, JSON construction, or platform-neutral runtime models.

## 6. Runtime Data Model

The runtime protocol should use explicit Codable DTOs rather than untyped
dictionaries or archived Objective-C object graphs.

Each hierarchy node should include at least:

- Session-scoped node ID.
- Parent ID and sibling index.
- Runtime class name and class chain.
- Node kind: view, layer, or semantic node.
- Frame and bounds in points.
- Visibility, hidden state, and alpha.
- Background color when available.
- Text preview when available.
- Accessibility identifier, label, value, traits, and enabled state.
- Supported detail categories.

`NodeRegistry` should assign monotonic IDs and retain runtime objects weakly.
Raw memory addresses must not become protocol identifiers because they can be
reused and expose implementation details.

## 7. Attribute Collection

Node details should be produced by composable collectors rather than a single
large switch or a generic KVC blueprint.

```swift
protocol RuntimeAttributeCollecting {
    func canCollect(object: AnyObject) -> Bool
    @MainActor
    func collect(object: AnyObject) -> [RuntimeAttribute]
}
```

The registry can execute every matching collector, allowing a UIButton to
receive common UIView, CALayer, UIControl, accessibility, and button-specific
attributes without coupling those implementations.

Initial collectors should prioritize properties currently used by Astrolabe:

- Text, font name, font size, text color, alignment, and line count.
- Background color, alpha, hidden state, clipping, corner radius, border, and
  shadow.
- Image presence, content mode, and image metadata.
- Control enabled, selected, highlighted, and button inset state.
- Scroll content size, inset, offset, and indicator state.
- Stack axis, alignment, distribution, and spacing.
- Content hugging and compression resistance priorities.
- Constraints affecting position and size.

## 8. Protocol

The initial protocol should use length-prefixed Codable JSON messages:

```text
UInt32 payloadLength (network byte order)
UTF-8 JSON payload
```

Every request contains:

- Request ID.
- Protocol version.
- Method.
- Typed parameters.

Every response contains:

- Matching request ID.
- Success state.
- Stable error code and recovery information on failure.
- Typed response payload on success.

The handshake returns runtime version, protocol range, platform, process
identity, and capabilities. Compression or a binary encoding should only be
introduced after hierarchy payload measurements show a concrete need.

## 9. Concurrency and Safety

- UIKit and CALayer access runs on `@MainActor`.
- Runtime objects never cross from the main actor into transport queues.
- Collectors convert runtime state into immutable DTO values before encoding.
- Transport and encoding run outside the main actor.
- Requests have explicit timeouts and cancellation.
- The server rejects oversized frames and unsupported protocol versions.
- The SDK is enabled only in Debug builds and while the App is inspectable.
- Inspection is read-only except for explicitly allowlisted, in-memory
  presentation-attribute patches used to validate UI hypotheses.
- The protocol exposes no arbitrary method execution or persistent mutation.

## 10. Migration

Completed runtime migration steps:

1. The platform-neutral wire contract, JSON Schemas, and fixtures live in the
   independent `astrolabe-protocol` repository.
2. Runtime and Host both lock `AstrolabeProtocol` to package version `1.0.0`.
3. The Runtime package no longer publishes or maintains a duplicate protocol
   target.
4. Handshake, App information, hierarchy, node detail, simulator TCP, and USB
   transport paths use the shared protocol models.
5. Protocol, Runtime, Host, Simulator, and USB verification are maintained at
   their owning repository boundaries.

The Host now registers only the project-owned iOS Runtime provider. The legacy
Lookin provider, archive decoder, shared models, and vendor path have been
removed from the production Runtime path.

The new Provider should use its own identifier and endpoint format during
migration. It should not disguise the new protocol as a Lookin-compatible
server.

### 10.1 Wire Protocol 2.0

The initial open-source package release is `1.0.0` and implements the
platform-neutral Wire Protocol 2.0 contract from `astrolabe-protocol` `1.0.0`.
Package release versions and Wire Protocol versions are independent.

The ownership boundary is strict:

- Protocol defines platform-neutral DTOs, values, extension rules, Schemas,
  Fixtures, and codecs.
- This repository owns UIKit, Core Animation, Auto Layout, iOS attribute
  identifiers, collection, mapping, listener lifecycle, and port selection.
- Astrolabe Host iOS targets own simulator/USB discovery and connection.
- Android-specific collection and mapping belong to
  `astrolabe-runtime-android`.

The iOS Runtime will map its platform objects into Protocol 2.0 DTOs. V2 does
not retain V1 compatibility fields merely to preserve Apple-specific names.

### 10.2 Runtime 2.0 Implementation Scope

Runtime 2.0 is a breaking architecture and protocol release, not a requirement
to add unrelated inspection features. Its required scope is:

1. Depend on `astrolabe-protocol` 2.0 and advertise Wire Protocol 2.0 during
   handshake without adding V1 DTO compatibility fields.
2. Introduce the Core, UIKit, facade, and test target boundaries described in
   Section 4.2 while preserving the existing `ASTRuntime` integration path.
3. Reduce accidental public API by changing cross-target infrastructure to
   `package` access and documenting the remaining supported public surface.
4. Establish an explicit UIKit-to-Protocol mapper. Platform-neutral semantics
   use Protocol fields; UIKit class names, Auto Layout facts, and iOS-only
   attributes remain Runtime-owned extension facts.
5. Keep capability advertisement derived from registered request handlers so
   handshake declarations cannot diverge from executable features.
6. Split macOS Core tests from iOS Simulator UIKit, facade, and Objective-C
   integration tests, then run both before the 2.0 release.
7. Update the Host iOS provider against Protocol 2.0 and repeat simulator and
   paired USB end-to-end regression validation before release.

The following improvements are valid 2.x candidates only after real UI samples
demonstrate a requirement:

- richer UIKit and public SwiftUI-hosting semantics;
- scene, window, scale, safe-area, and capture consistency metadata;
- App-configurable privacy and redaction hooks;
- hierarchy payload reduction or bounded subtree requests;
- additional allowlisted presentation patches.

V2 does not create an `astrolabe-runtime-core` repository, share Swift Runtime
implementation with Android, introduce arbitrary method invocation, or expose
unrestricted property mutation. Android reuses the Wire Protocol contract and
Fixtures, not the iOS implementation.

## 11. Acceptance Criteria

- Host discovery identifies simulator and USB runtime endpoints across App
  restarts.
- Hierarchy captures match visible UIKit/CALayer structure on representative
  screens.
- Node details cover every semantic attribute required by V1 checks.
- Existing CLI and MCP commands operate without command-layer changes.
- High-fidelity screenshots and visual diff continue to use host-side capture.
- No Lookin archive or shared model is required at runtime.
- The iOS runtime package contains only documented inspection capabilities and
  allowlisted temporary presentation-attribute patches; arbitrary method
  invocation and persistent mutation remain unsupported.
