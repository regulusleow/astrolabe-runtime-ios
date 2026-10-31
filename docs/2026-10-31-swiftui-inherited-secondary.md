# SwiftUI inherited secondary color verification

## Supported increment

Inherited secondary text color now resolves from a proven pure Color base, including system colors, sRGB, constructor alpha, Color.opacity wrappers, font modifier order, nearest overrides, normalized nested secondary and tint bases. A directly supplied Color.secondary modifier uses the same validation and calculation. An explicit secondary style in a two/three-level foreground pack is selected directly and is not attenuated again; its known Color or tint path is reused.

The implementation preserves current-node environment lookup, first-entry finality, explicit original Text color priority, shared/local budgets, secure-input suppression and frozen snapshot projection. Host, Protocol, MCP tools, dependencies and Demo source are unchanged.

## Design and trust boundary

- SwiftUIEnvironmentColorReader remains the bounded private environment adapter. A shared unbox helper reads only AnyShapeStyle storage; exact metadata policy predicates admit the observed offset, Color modifier and pair/triple forms. Only offset/level1 is accepted. Unknown or unsupported styles never fall back to an outer foreground color.
- SwiftUISecondaryColorResolver isolates one native Swift ABI call. No provider registry, new public interface or shared data model is introduced.
- The native exported function is `SwiftUI.Color.multiplyingHierarchicalOpacity(at:)`, mangled `$s7SwiftUI5ColorV30multiplyingHierarchicalOpacity2atACSi_tF`. The observed frozen ABI passes the level and one-word Color in x0/x1 and returns a new Color. Independent compiler SIL confirms `(Int, @guaranteed Color) -> @owned Color`, matching the saved disassembly and retain behavior.
- The bridge is enabled only for iOS27.0 arm64 simulators. It requires verified value/function sizes, exact symbol name/address, and the same loaded image as Color canonical metadata. A missing or mismatched symbol returns no color.
- The entire original Color provider chain and resolved RGBA are validated before calling the bridge. This prevents invalid source alpha from becoming apparently valid after hierarchical attenuation. The returned HierarchicalOpacityColor wrapper, level1 and original provider identity are checked under the same budgets before public Color.resolve(in:) in the node environment.
- SwiftUI computes hierarchical opacity. The product contains no hardcoded alpha multiplier or replacement system gray. A separate synthetic public ShapeStyle paint probe agrees with the direct native bridge for RGB, alpha, constructor alpha and system-color samples.

## Verification

- Actual baseline source-MCP REDs: Secondary RGB and an explicit secondary level have real semantic nodes but no common.text.color. Pure trust-policy positive assertions also fail before implementation; no UI unit tests were added.
- Full Runtime XCTest suite passes67 tests: UIKit policy/facts23, module boundary3, ObjC2, Core39. The initial default build cache contained test bundles rejected by code-signature policy; a fresh scratch run passed. After swift package clean, the default swift test command also passes all67. No system policy was disabled.
- iOS Simulator framework and source Host builds succeed with Xcode27.2 / Swift6.4.2. Actual loaded changed framework ARM64 UUID: `0F7BEA8C-A4E3-3AB1-90F1-D4DBCE1F3BE4`.
- Real acceptance: iPhone18Pro, iOS27.0 (24A434), dedicated bundle `dev.astrolabe.SwiftUIForegroundTest`, PID11645. Each state starts with source-MCP list_apps compatibility and a new inspect_screen snapshot; details use that same snapshot and runtimeSnapshot source.
- Primary21 cases pass in each appearance, with18 expected colors and3 deliberate absences. They cover RGB/system/alpha, both font orders, normalized hierarchy, nearest/explicit overrides, explicit pair/triple level selection, direct Color modifier, tint and direct-color references.
- Edge/regression16 cases pass in each appearance, with6 expected colors and10 absences. They reject invalid RGB, constructor alpha and opacity factor; tertiary forms; excessive wrappers; explicit invalid color; gradient/unknown selected levels; and a UIKit-backed direct modifier. Explicit secondary opacity/tint and plain tint/opacity/font continue to work. The deep case reports truncation and budgetExceeded.
- All37 old light details retain identical decoded attributes and full semanticContext after dark captures (the primary frozen read also overlaps the next fixture transition). RGBA tolerance is0.00001. Font size checks include the scaledLogical unit.
- A public UITextField check confirms a filled synthetic secure value. Six inherited/direct/explicit-level/tint/explicit-Color/font nodes expose no common text attributes or text candidates and carry secureInputContext. Neither screen nor detail JSON contains the synthetic input.
- A controlled inspect_screen read leaves the original before/after PNG byte-identical (242193 bytes each; SHA256 `42b65463687ae4b4fbb256af1d37446832a2632bffb348e15bbf1150a20db2f0`). Independent decoded-pixel comparison also gives zero differences. An inconsistent image presentation initially suggested missing text; the original files and pixels do not support a Runtime visual change.
- Independent review found no blocking defects in selection, ABI ownership, budgets or projector integration. CodeGraph synchronized; git diff --check passes.

## Capture identities and artifacts

| Capture | Snapshot ID | Cases |
| --- | --- | --- |
| Primary light | 0FACE76F-C48E-4239-AF25-3ABD5E71CE67 | 21 |
| Primary dark | C6092CDB-7449-4A9A-9596-8A447C44ECA0 | 21 |
| Edge/regression light | 335546BC-02C4-4C90-AB8B-93C68348B87E | 16 |
| Edge/regression dark | 2D2E856A-BE84-4839-9007-ED52FF27086D | 16 |
| Filled secure input | 74C01AAA-C66F-4B11-B454-BACA7CDEE9B4 | 6 suppressed nodes |
| Clean ordinary Demo | E50FDC4F-B760-44FA-81B0-F03903B73C32 | Compatible, no fixture modules |

Artifact directory: `/var/folders/0m/gdyng10s0p3fb_zz561qvsxc0000gn/T/astrolabe-secondary-20261031-g6b2lakk`.

Summaries: `secondary-final-summary.json`, `secondary-edge-summary.json`, `secondary-privacy-summary.json`, `readonly-control-summary.json`, `clean-summary.json`. Research: `secondary-probe.json`, `hierarchy-address.log`, `hierarchy-bridge.json`, `shape-paint-oracle.json`, `oracle-dark-summary.json`. Verification: `policy-red.log`, `runtime-tests.log`, `default-tests-after-clean.log`, `runtime-build.log`, `secondary-final-accept.log`, `secondary-edge-accept.log`, `secondary-privacy.log`. Source MCP screenshots use secondary-final/secondary-edge light/dark prefixes.

After acceptance the Demo was restarted with only the new Runtime, PID13650. The loaded image UUID was confirmed, all temporary fixture/probe libraries were absent, and the original app was captured again. Existing Demo README/handoff changes were preserved. Snapshot IDs above are historical evidence and are not guaranteed to remain queryable after restart or cache expiry.

## Limits

The native hierarchy bridge is not enabled on hardware, x86_64 simulators or other OS versions. Those targets have not been validated. Default SystemColorsStyle, tertiary, materials, gradients, unknown providers and deeper compound hierarchy remain unavailable. Existing exclusive depth20 and visit budgets may refuse complex otherwise recognizable styles earlier. The attribute describes resolved text style RGBA, not compositing through View.opacity, blend modes or a background. Private ABI/layout changes require new evidence before widening support.
