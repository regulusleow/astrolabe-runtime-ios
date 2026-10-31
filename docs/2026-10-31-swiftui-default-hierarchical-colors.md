# SwiftUI default and tertiary foreground verification

## Supported increment

Default system secondary/tertiary text colors and tertiary styles derived from
proven pure Color bases now export `common.text.color`. Explicit foreground
packs select their actual secondary/tertiary field, without applying hierarchy
opacity a second time. This closes the proven default and tertiary paths before
integration and release validation.

## Design and evidence

- Keep selection and bounded traversal in SwiftUIEnvironmentColorReader, exact
  metadata checks in SwiftUITextMetadataPolicy and color calculation in the
  renamed SwiftUIHierarchicalColorResolver. No compatibility aliases, provider
  registry, public API, shared model, dependency or Host/Protocol change.
- Accept only hierarchy levels 1 and 2. The default path requires the exact
  SwiftUI-owned OffsetShapeStyle<SystemColorsStyle> box, its expected superclass,
  an empty typed base and no background material. Resolve Color.secondary or
  Color(uiColor: .tertiaryLabel) in the captured node environment. This narrow
  mapping does not admit arbitrary UIKit-backed inherited providers.
- An independent public ShapeStyle paint probe records actual SwiftUI paint
  results for ten samples per appearance. Default secondary/tertiary agree with
  those semantic colors in both standard and increased contrast. Material-based
  defaults produce no solid Color result and remain unavailable.
- Pure-color tertiary reuses the existing verified native
  `Color.multiplyingHierarchicalOpacity(at:)` bridge with level 2. The probe
  observes alpha 0.25 for an opaque custom RGB tertiary; the product contains no
  replacement multiplier. The iOS 27.0 arm64-simulator, ABI, symbol and loaded
  image checks remain in place. Original provider/RGBA and returned wrapper,
  level and provider identity are validated before exporting the result.
- Actual paint output confirms that a two-style pack reuses its secondary for
  a tertiary child, while a three-style pack selects its explicit tertiary.
  The chosen known Color/tint follows the existing resolver without attenuation;
  an unsupported chosen field is final, even when an outer color is available.
- Default and existing paths share one finite, in-range RGBA projection. Original
  Text priority, nearest-entry finality, provenance, budgets, privacy suppression
  and frozen snapshot storage retain their existing implementations.

## Verification

- Baseline source-MCP captures contain the real default-secondary and inherited
  tertiary semantic nodes but no color; expected-color assertions fail. The new
  pure trust/level policy assertions also fail before implementation. No UI unit
  tests were added.
- All 69 Runtime XCTest checks pass: UIKit policy/facts 25, module boundary 3,
  ObjC 2 and Core 39. The iOS Simulator framework builds successfully with
  Xcode 27.2 / Swift 6.4.2. CodeGraph is synchronized and `git diff --check` passes.
- Live target: iPhone 18 Pro arm64 simulator, iOS 27.0 (24A434), dedicated bundle
  `dev.astrolabe.SwiftUIForegroundTest`, PID 16264. The loaded changed framework
  UUID is `9FD92D1F-66AF-398E-AC81-A2C3C3DDAC36`. Each capture starts with source-MCP
  compatibility discovery; node details use the captured snapshot and
  `runtimeSnapshot` source.
- Primary 22 scenarios pass in each appearance: default and increased-contrast
  system levels, both font orders, inherited/direct tertiary RGB and alpha,
  explicit pair/triple selection, tint, explicit priority and secondary
  regression, with quaternary/material/gradient absences. Nineteen expect color.
- Edge/regression 19 scenarios pass in each appearance: invalid RGB/alpha/factors,
  unknown UIKit providers, selected gradient/unknown styles, unused unsupported
  levels, explicit opacity, quaternary, excessive wrappers, secondary alpha,
  plain opacity/tint and nil-tint reset. Eight expect color. The deep case reports
  truncation and `budgetExceeded`.
- All 41 old light details retain identical decoded attributes and complete
  semanticContext after dark captures. RGBA tolerance is 0.00001; font checks
  include size 18 and its `scaledLogical` unit.
- A public UITextField check confirms a filled synthetic secure input. Seven
  default/inherited/direct/explicit-level nodes expose no common text attributes
  or text candidates and carry `secureInputContext`. Neither screen nor details
  contain the synthetic value.
- A controlled inspect_screen read leaves before/after PNGs byte-identical:
  SHA256 `5e859e73598f92189f76cdb827fc5b52c6cfb55a46cfdf04e166687c190cca2c`.
  Independent decoded body-pixel comparison also reports zero changes.
- Independent review found no concrete defects in trust checks, level selection,
  precedence, budgets or integration. After acceptance, the Demo was restarted
  with only the new Runtime, PID 18078. Its UUID and compatible discovery were
  confirmed, temporary fixture/probe modules were absent, and the ordinary Demo
  was captured again. Pre-existing Demo README/handoff edits were preserved.

## Capture identities and artifacts

| Capture | Snapshot ID | Cases |
| --- | --- | --- |
| Primary light | 4D7DF5E2-CB22-4261-80CC-3D85C2A41BF6 | 22 |
| Primary dark | AFC19214-BB93-4490-A9ED-F6903EE20247 | 22 |
| Edge/regression light | E358FBA6-2921-475A-82DD-FD918FE4C0CE | 19 |
| Edge/regression dark | CDA2175D-7060-491A-A2AD-F0E508FED4C3 | 19 |
| Filled secure input | 3B5BEA72-90F1-40B7-80EC-3341B9B85E14 | 7 suppressed nodes |
| Clean ordinary Demo | D667419F-0DA4-452C-8098-8E61BBB917BE | Compatible, no temporary modules |

Artifact directory:
`/var/folders/0m/gdyng10s0p3fb_zz561qvsxc0000gn/T/astrolabe-hierarchy-20261031-6l06nbgw`.

Research: `oracle-summary.json`, `oracle-light.json`, `oracle-dark.json` and
`hierarchy-node-probe.json`. Acceptance: `hierarchy-summary.json`,
`hierarchy-edge-summary.json`, `hierarchy-privacy-summary.json`, the corresponding
acceptance logs and light/dark PNGs. Build/policy: `policy-red.log`,
`runtime-tests.log`, `runtime-build.log`. Controls: `readonly-before.png`,
`readonly-after.png`, `readonly-pixels.log`, `secure-filled.log`,
`clean-images.log`, `clean-summary.json` and `clean.png`. Snapshot IDs are
historical evidence and may expire after restart or cache eviction.

## Limits

Only iOS 27.0 arm64 simulators are enabled for the native hierarchy and default
palette paths. Hardware and other OS/architecture combinations need independent
evidence. Private layout drift, unsupported providers, default primary/nil tint,
higher hierarchy, non-solid paint and exhausted budgets remain unavailable.
Resolved style RGBA does not describe final compositing or glyph rasterization.
