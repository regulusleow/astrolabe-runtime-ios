# Verified SwiftUI inspection support

This is the functional scope for the current release candidate work. It freezes
the proven inspection paths; it does not claim complete SwiftUI support. The
package's iOS 15 minimum remains separate from these private-layout adapters.

## Verified environment

The latest acceptance uses Xcode 27.2 / Swift 6.4.2 and an iPhone 18 Pro arm64
simulator running iOS 27.0 (24A434), through the source Host and MCP adapter.
The environment-color adapter requires iOS 27.0. Native hierarchical-color
calculation and the default system-palette mapping additionally require an
arm64 simulator. Hardware, other architectures and other OS versions have not
been validated for these paths. A matching version alone is insufficient when
metadata, storage, symbol or traversal checks fail.

## Supported paths

| Area | Verified behavior and boundary |
| --- | --- |
| Text scope | Project confirmed original Text attributes into the existing semantic node. Inherited attributes require a unique, complete original Text scope. Ambiguous scope remains partial or unavailable. |
| Font | Resolve explicit fonts and, when no explicit font exists, the current node's environment font. Export confirmed font name, size in `scaledLogical`, bold and monospaced facts. An explicit but unresolved font blocks inheritance. |
| Pure color | Resolve proven SwiftUI system and sRGB Color providers, constructor alpha and bounded `Color.opacity` chains in the current node environment. Every component and opacity factor must be finite and within 0...1. |
| Tint | Resolve a foreground tint style through the nearest explicit, non-nil, proven pure Color TintKey. Unsupported or nil tint is final; no accent-color substitution. |
| Inherited hierarchy | Resolve secondary and tertiary from a proven pure Color or tint base through SwiftUI's native hierarchical calculation. Direct hierarchical Color modifiers use the same validation. No product alpha multiplier is supplied. |
| Default hierarchy | Resolve secondary and tertiary only from the exact, empty SystemColorsStyle base without background material. Use the actual node environment, including light/dark appearance and increased contrast. |
| Explicit hierarchy levels | For a secondary/tertiary child of a two/three-style pack, select the explicit level. A pair reuses its secondary at tertiary; a triple selects its tertiary. The selected pure Color or tint is not attenuated again. |
| Precedence | Original explicit Text color wins, including when it cannot be exported. The nearest matching environment entry is final; an unsupported inner style never falls back to an outer color. |
| Capture guarantees | Preserve source paths, typed candidates, shared/local budgets, secure-input suppression and frozen snapshot values. Missing evidence stays unavailable; style checks cannot treat missing attributes as a successful match. |

The four-wrapper opacity cap, eight environment-hop cap and exclusive depth
limit of 20 are upper bounds, not promises that every combination fits. Earlier
entries and nested styles consume the same budgets and can cause refusal sooner.

## Outside the frozen scope

- Implicit default primary color when the absence of a foreground entry cannot
  be proven; primary selection from a style pack without a secondary/tertiary
  child; quaternary, quinary and unrecognized compound hierarchy.
- Default/nil tint, unknown Color providers and unsupported private layouts.
- Recovering material, vibrancy, gradient or image-paint results as a solid color.
- Arbitrary color-space/HDR recovery and out-of-range color values.
- Final pixel compositing through View opacity, blend modes or backgrounds;
  complete SwiftUI view trees, occlusion and per-glyph fallback/run reconstruction.
- SwiftUI-specific mutation support. The UIKit patch catalog is a separate
  capability and is not widened by these inspection changes.

## Evidence and next gate

The [latest verification report](2026-10-31-swiftui-default-hierarchical-colors.md)
records 69 passing Runtime XCTest checks, 41 live scenarios in each appearance,
41 frozen-detail comparisons, seven filled-secure-input suppressions and a
byte-identical screenshot control. Earlier reports cover
[font](2026-10-22-swiftui-inherited-font.md),
[sRGB](2026-10-30-swiftui-inherited-rgb.md),
[opacity](2026-10-31-swiftui-inherited-color-opacity.md),
[tint](2026-10-31-swiftui-inherited-tint.md) and
[secondary](2026-10-31-swiftui-inherited-secondary.md) increments. Their remaining-work
sections describe their historical baseline; this matrix is the current scope.

The next gate is four-repository integration and release validation: real
devices, mixed-device discovery, performance/budget behavior, privacy and
dependency security review. Expanding the unsupported style list is separate
feature work, not a prerequisite silently added to that gate.
