# SwiftUI inherited Color.opacity verification

## Scope and design

Inherited foreground colors now accept `Color.opacity` when every nested provider is a proven SwiftUI system or resolved color. The reader validates the complete provider chain, then uses the original `Color.resolve(in:)` in the captured node environment. Constructor alpha and nested factors are multiplied by SwiftUI, without a separate color conversion.

The change stays inside the existing iOS 27.0 environment adapter and metadata policy. Original Text scope, explicit-color priority, canonical projection, secure-input suppression, shared budgets and snapshot storage retain their existing paths. There are no shared-contract, dependency, Host or MCP changes.

Unknown inner providers, invalid opacity factors, gradients, hierarchical styles and tint styles remain unavailable. The first foreground entry is final; unsupported inner styles never reveal an outer color. Accepted opacity factors are finite and within 0...1. The wrapper loop has an upper cap of four, but the exclusive local depth limit of 20 can reject earlier: a head foreground entry admits at most three wrappers, and preceding environment entries consume additional depth.

## Verification

- Pure metadata-policy RED observed before implementation; all 62 Runtime XCTest tests pass afterward. No UI unit tests were added.
- Baseline and changed Runtime iOS Simulator framework builds succeed with Xcode 27.2. Source Host builds successfully.
- Real acceptance target: iPhone 18 Pro simulator, iOS 27.0 (24A434), dedicated bundle `dev.astrolabe.SwiftUIForegroundTest`. Loaded changed framework ARM64 UUID: `000B3C25-F57A-318E-87AA-CE9AC3711027`.
- Source MCP reproduces missing inherited opacity color on the baseline Runtime with the target semantic node present. Earlier attempts with unavailable accessibility nodes are excluded from behavior evidence.
- Nineteen cases pass in each of light and dark appearance: RGB, constructor-alpha multiplication, nested opacity, zero alpha, dynamic system red, font modifier order, nearest override, explicit-color priority, invalid explicit color, unknown UIKit-backed base, out-of-range factors, excessive wrappers, unsupported secondary/tint/gradient, and plain RGB/system-color regressions. Each appearance has eleven expected colors and eight expected absences; RGBA tolerance is 0.00001.
- Nineteen old light-snapshot details remain byte-equivalent at the decoded attribute and semantic-context level after the dark capture.
- Three secure-input contexts suppress text candidates and common text attributes. A separate public UITextField check confirms that the synthetic secure value was actually filled; it is absent from capture and detail JSON.
- Source MCP screenshots were reviewed. Independent code review found no defects in the increment; CodeGraph was synchronized and `git diff --check` passes.

## Evidence

Local artifact directory: `/tmp/astrolabe-swiftui-foreground-20261030-48a507tv`.

| Capture | Snapshot ID | Assertions |
| --- | --- | --- |
| Light | A3DCF849-E544-4457-BC1B-51F36A425930 | 19 |
| Dark | 99B68A77-7ADF-431B-BF41-4A89BB05768B | 19 |
| Frozen light details | A3DCF849-E544-4457-BC1B-51F36A425930 | 19 |
| Filled secure inputs | 1F37D733-686E-4AE0-8C83-CE1EB196DF6C | 3 suppressed nodes |

Summaries: `opacity-accept-summary.json` and `opacity-privacy-summary.json`. Logs: `policy-red.log`, `runtime-tests.log`, `runtime-ios-build.log`, `product-red-live.log`, `opacity-accept.log`, `opacity-privacy.log`. Screenshots: `opacity-light.png` and `opacity-dark.png`.

## Limits

This evidence covers the existing iOS 27.0 private-layout adapter on a simulator, not other OS versions or hardware. It describes the text color attribute, not final compositing through View.opacity, materials or blend modes. Secondary and tint style resolution remain separate work; unknown layouts continue to return no color.
