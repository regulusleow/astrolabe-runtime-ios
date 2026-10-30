# SwiftUI inherited tint verification

## Scope and design

A foreground `TintShapeStyle` now resolves a proven pure color from the current accessibility node's nearest `TintKey`. The existing private environment reader shares one bounded singleton lookup for foreground and tint entries. It recognizes only the verified Font/ForegroundStyle/Tint layouts and rejects unknown or merged storage.

Tint lookup requires an exact SwiftUI-owned anonymous-context ShapeStyleBox type, its AnyShapeStyleBox superclass, and a typed TintShapeStyle base. The selected tint then passes the existing complete Color provider validation, including bounded opacity wrappers, before public Color resolution in the captured environment. Neither TintShapeStyle.resolve nor a substitute accent color is called.

Both lookups share the same local and global visit budgets. The eight-hop cap and exclusive depth limit remain in place; a longer path can be rejected earlier. The first requested key is final even when nil or unsupported. There is no outer-color fallback or recursive tint resolution. A verified TintKey can also be skipped while locating a direct foreground color.

Original Text scope, explicit-color priority, secure-input suppression, canonical projection and frozen snapshot storage retain their existing implementations. There are no Protocol, Host, MCP or dependency changes.

## Verification

- Live source-MCP RED: the opacity-only Runtime exposed the target Tint RGB last node but no common.text.color; the expected-color assertion failed.
- Pure TintKey and tint-style-box policy assertions fail before implementation; all 64 Runtime XCTest tests pass afterward. These checks instantiate no UI; no UI unit tests were added.
- Changed Runtime iOS Simulator framework build succeeds with Xcode 27.2. Actual loaded ARM64 UUID: `655A5BF5-D42E-3CD5-9D5D-88609BA42A51`.
- Real target: iPhone 18 Pro simulator, iOS 27.0 (24A434), dedicated bundle `dev.astrolabe.SwiftUIForegroundTest`, PID 14745.
- Nineteen tint cases pass in each appearance: modifier order, RGB, dynamic system orange, opacity and constructor alpha, nearest tint, explicit blue/invalid color priority, nil reset, gradient, unknown provider, invalid factor, font order, direct foreground under tint, unsupported secondary/gradient and an orange reference. Each appearance has twelve expected colors and seven expected absences; RGBA tolerance is 0.00001. Tint-origin fields carry a TintKey provenance path.
- All nineteen prior opacity cases pass again in each appearance, with the formerly unsupported tint example now returning the independently captured orange reference. Each appearance has twelve expected colors and seven expected absences.
- All nineteen old light details in each fixture remain unchanged at decoded attribute and semantic-context level after dark captures.
- A public UITextField check confirms a filled synthetic secure value. Three text nodes (inherited tint with opacity, explicit opacity, inherited font plus tint) expose no common text attributes or text candidates and carry the secure-input issue. The synthetic value is absent from screen and detail JSON.
- Source MCP screenshots were reviewed. Independent static review found no defects. CodeGraph synchronized; git diff --check passes.

## Evidence

Artifact directory: `/tmp/astrolabe-swiftui-foreground-20261030-48a507tv`.

| Capture | Snapshot ID | Cases |
| --- | --- | --- |
| Tint light | 60D63D99-F008-41AA-9588-F70273396795 | 19 |
| Tint dark | 270708C7-4B09-40A1-A5D3-3F136ED724CA | 19 |
| Opacity regression light | CE6C4F40-2A79-4C8E-8894-6DB7DF3EF0C5 | 19 |
| Opacity regression dark | EFE9B3EC-E978-4505-A2AF-76D0CA7D5F2F | 19 |
| Filled secure input | 2E874337-0905-4F80-895D-726F27B27B45 | 3 suppressed nodes |

Summaries: `tint-accept-summary.json`, `opacity-regression-accept-summary.json`, `tint-privacy-summary.json`. Logs: `tint-product-red.log`, `tint-policy-red-assertion.log`, `tint-runtime-tests.log`, `tint-ios-build-corrected.log`, `tint-accept.log`, `opacity-regression-accept.log`, `tint-privacy.log`. Screenshots: `tint-light.png`, `tint-dark.png`.

## Remaining boundary: secondary

The actual inherited secondary sample is a `ShapeStyleBox<OffsetShapeStyle<AnyShapeStyle>>`, not a ColorBox. The available SDK declares HierarchicalShapeStyle.Resolved and TintShapeStyle.Resolved as Never, so their generic resolver cannot provide a color. Resolving Color.secondary instead produces a system secondary color rather than proving the sample's inherited base-style rendering. The reader therefore keeps secondary unavailable rather than substituting a gray or guessed opacity. Extending this requires evidence for the bounded offset/base-style representation and its final paint result.

This increment covers the existing iOS 27.0 private-layout adapter on a simulator. Default/nil tint, non-color styles, unknown providers and other OS layouts remain unavailable. Final compositing through View.opacity, materials and blend modes is outside the common text color attribute.
