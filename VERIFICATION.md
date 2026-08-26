# Verification

CodexTokenLedger **2.1.0 (build 22)** was verified on 2026-08-26 with Xcode
26.4 / Swift 6.3.

## Automated tests

```bash
xcodegen generate
xcodebuild test \
  -project CodexTokenLedger.xcodeproj \
  -scheme CodexTokenLedger \
  -configuration Debug \
  -destination 'platform=macOS'
```

Result: **73 tests, 72 passed, 1 network-gated skip, 0 failures**.
Final repository test log: `build/repository-initial-test.log`.
The Token detail row layout was also verified independently by its rendered Overview
test and source contract (`build/test-token-detail-row-layout.log`,
`build/test-token-detail-row-contract.log`).

The suite covers exact Codex counters, duplicate/regressed events, concurrent
active tasks, title evidence, account RPC parsing, quota forecasts, GPT-5.6
request-scoped long-context pricing, Token/JSON/JSONL/Sub2/CPA/Cockpit imports,
monitor/sign-in modes, append-aware live-context caching, seven-locale i18n,
Tibo source filtering and reset-cycle state transitions.

Visual regression additionally enforces:

- production presentation through `NSStatusItem -> NSMenu -> NSMenuItem.view`;
- AppKit-owned transparent native menu glass rather than an opaque SwiftUI root;
- immediate System/Light/Dark propagation;
- no dashboard `ScrollView`, scrollbar or hidden scrolling container;
- 12pt minimum explicit visible type, no scale-to-fit and no wrapped labels;
- a fixed 340pt menu width;
- a continuous blurred upper gradient which fades through the section boundary;
- an AppKit top-inset bridge which shares the hero's translucent top palette,
  accepts only a real 0.5-12pt native gap and ends exactly at the SwiftUI edge;
  it no longer samples timing-dependent pixels, overlaps the hero or turns a
  transient menu-window measurement into a clipped identity row;
- detail disclosure is a floating layer inside the existing hero bounds and never
  participates in intrinsic layout; Light and Dark fixtures prove collapsed and expanded
  overview heights are exactly equal;
- disclosure never increments the AppKit layout revision or resizes the `NSMenu`; only
  the local drawer and chevron animate, eliminating whole-window flash and scrollbar jumps;
- the detail drawer uses adaptive thin-material frost with a restrained blue-white/navy
  tint and dedicated high-contrast ink; the hero colour can diffuse through the glass
  without allowing background content to overpower the Token evidence;
- settled AppKit measurement skips an identical second `NSMenu` update, preventing a
  delayed window nudge after the disclosure has already reached its final size;
- the entire blue hero now uses white/high-white ink in both appearances—including
  context limits, percentages, metric tiles and the selected context scope; the selected
  scope uses a darker translucent blue capsule instead of black text on white;
- the hero refresh icon accepts explicit idle/spinning colours and stays white in Light
  mode rather than falling back to the component's default dark ink;
- Light mode uses blue-graphite ink and blue-grey secondary text instead of harsh
  neutral black, preserving contrast without looking detached from the hero field;
- an independently rendered hero account label layered above the transparent native
  `Menu` hit target, preventing AppKit from forcing the email to black in Light mode;
- a restrained blue-only hero gradient with one soft radial sheen—no competing cyan/
  teal wash, coloured card outlines or stacked milky overlays;
- standard SF typography with semibold hierarchy, no rounded-display type throughout
  every label and no decorative drop shadows;
- active tasks use a quiet underline rather than nested pill containers, secondary
  metrics are flat inside their parent surface, and the footer no longer forms a band;
- request input and generated output now have explicit raster direction markers:
  input points down into the model, output points up from the model, while cached
  input keeps a separate reuse symbol;
- the Overview primary metric defaults to **Conversation context** and reads only
  `lastRequest.inputTokens`; **Task usage total** remains a separate selector and
  is explicitly labelled cumulative usage rather than context size;
- the context breakdown is scope-aligned: context input, the cached portion inside
  that input, and the latest request output all come from the same accepted model
  request—never from the larger current-turn or task aggregate;
- the floating Token detail view separates conversation context, current turn and
  task cumulative usage into divided sections; every section presents input,
  included cache and output as separate label/value rows so large exact counters never
  collide, and the pricing area
  labels each standard or long-context rate instead of presenting an unlabeled slash list;
  compact totals and every exact counter display the Token unit, while every API rate
  states that it is priced per 1M Token;
- the native status item uses one metric-specific raster glyph plus a compact 12.5pt
  monospaced value; context input is a downward arrow and concurrent tasks read as `×N`,
  while icon-only mode uses the full-colour AppIcon;
- Overview, Local Ledger and every Control Center tab are all exactly 340x705; switching
  Theme, Live, Accounts or Local Data no longer remeasures the native menu;
- Local Ledger now displays eight real 52pt task rows per page and anchors its explicit
  pager above the footer, using the previously empty lower region without scrolling;
- each Control Center panel keeps the same fixed window height while related setting groups
  remain adjacent with a 14pt section gap instead of a large elastic gap through the middle;
- the developer page now shares the full 340x705 primary-page size, uses a 146pt avatar,
  keeps one short localized product line, and reads the version from the built bundle;
- the image-generated AppIcon uses a flat two-line `CODEX` wordmark at every supplied
  macOS icon size; the developer product card uses that AppIcon, while the Overview
  identity row uses its single-colour transparent raster mark so it inherits the hero ink;
- live token updates rely on numeric content transitions and never flash the entire hero;
- a 14pt hero-bottom fade allowance instead of 42pt, keeping the transition soft
  without the oversized blank band before Updates;
- Task, Quota and Account use one fixed 142pt `ZStack`; tab changes only crossfade
  those local layers, never use horizontal move transitions, change intrinsic height,
  or call `menuLayoutChanged`, so the native menu does not shake or remeasure;
- raster product and functional icons with no runtime SVG assets.

## Reference-led visual result

The 2.1 overview now follows the supplied reference hierarchy:

1. identity and account;
2. a directly visible multi-task ribbon;
3. one oversized real context-input number;
4. three translucent input/cache/output tiles with down/reuse/up direction markers;
5. one segmented Updates surface;
6. minimal bottom navigation.

Blue remains the interaction/selection and healthy-value text accent; green is limited to small live/valid state indicators. The blue field is not a rounded card or a collection of circular glows. Its
vertical gradient and blurred diagonal tint are drawn behind the entire overview,
then reduce to zero opacity after entering the lower adaptive material. This
removes the hard horizontal seam in both light and dark appearances.

Key fixtures:

```text
Design/AppIconMaster.png                              1024x1024
Design/BrandMarkMaster.png                            1024x1024
build/AppIcon-size-preview.png                       720x240
build/CodexTokenLedger-v2.1-preview-light.png        340x705
build/CodexTokenLedger-v2.1-preview-dark.png         340x705
build/CodexTokenLedger-v2.1-details-light.png        340x705
build/CodexTokenLedger-v2.1-details-dark.png         340x705
build/CodexTokenLedger-v2.1-sessions-light.png       340x705
build/CodexTokenLedger-v2.1-tibo-signal-light.png    340x258
build/CodexTokenLedger-v2.1-console-light.png        340x705
build/CodexTokenLedger-v2.1-live-settings-light.png  340x705
build/CodexTokenLedger-v2.1-accounts-light.png       340x705
build/CodexTokenLedger-v2.1-data-settings-light.png  340x705
build/CodexTokenLedger-v2.1-token-login-light.png    340x468
build/CodexTokenLedger-v2.1-developer.png            340x705
build/CodexTokenLedger-v2.1-developer-dark.png       340x705
```

Key SHA-256 values:

```text
AppIcon master: ccdd96d9fb52763422244034ee02a84f2ac6a585ac3bb3f01863d01297b02d21
brand mark:     9bcca28832551075cd96480e78a68dd5cd1c1114589d9c0ce0232b88a8b27e73
overview light: 7b6310a3ff48e2ee25f78a9fc74638ad41de14a76d08fdd5b00163c79d189ca4
overview dark:  4b442921e9b07c917f44a444bdbcf87010753b44ea0b223eec155227e77d67b4
details light:  e4d36020b7eb529519a93b50848a9e57dc7b063280008b4a4123da5a52d5f497
details dark:   cf18aae9a8178cfb752107391c084b7ce530b66af2b03e96a8461a9a7c2e60c3
sessions light: 3fb2b731da4e8b343d45ad8b276cdc2434485c0e8061090e10c55669dbf42725
console light:  f5776f60e7e7ae504a1191379d260d10d8f242254114d9ed57861f3552d24cde
accounts light: aa511bab5b4480c76a13c3877da4d7fc35467d14de5cf00620dab90b380843ae
data light:     27946e607a013ea4714dc3460b45b125fc26f7ef8ded9b620b98d318572cfde4
Tibo light:     30c904edc4de08a7b4c755d5bcca9b9748898ea1b3968aef386aa9877020d1d1
developer:      81e197c6b68685a0e280b9724af7f0198d28379a464d34126cee53126dd562e4
developer dark: fdba56a132c9cc7ae62c996240a48ca8dcad4b604b0ca109595c96d9cf377bf5
```

## Tibo reset-cycle evidence

Tibo remains independent from account 5-hour/weekly quota. The Overview row and More control open
the dedicated three-point cycle page: latest confirmed reset, current signal,
and structured prediction or seven-day baseline. No version/hash/post-ID/source
dump is shown in the user interface.

The unchanged production service remains aligned with
[`Dopetaiga/tibo-watch`](https://github.com/Dopetaiga/tibo-watch), commit
`242735d0858c961b6d9f4db2468f114f02d8a71e`. Its MIT license is bundled as
`TiboWatch-LICENSE.txt`.

The last live public-source audit is retained at
`build/tibo-signal-audit-v2.0.json` (service code unchanged):

```text
SHA-256: fd826035f64a24eaf1ba1c810831d249ae7c5c1aa01081428ce24aa2d769e985
sourceStatus: healthy
postID: 2091688655828246890
postedAt: 2026-08-24T00:46:51Z
status: confirmed
matchedRuleIDs: reset-propagated-completed
```

The artifact contains no post body.

## i18n

```text
Source: Sources/CodexTokenLedger/Resources/Localizable.xcstrings
SHA-256: e550bcb4abc7548f9e29b5389192922605b214392404a008cf38da70872bbced
String Catalog keys: 326
Locales: en, zh-Hans, zh-Hant, ja, ko, es, fr
Missing explicit locale entries: 0
Compiled .lproj resources: 7
```

## Release build and package

```bash
xcodebuild -project CodexTokenLedger.xcodeproj -scheme CodexTokenLedger \
  -configuration Release -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData ARCHS='arm64 x86_64' \
  ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO build \
  | tee build/release-build-v2.1-token-detail-rows.log
./scripts/package_release.sh | tee build/package-v2.1-token-detail-rows.log
codesign --verify --deep --strict --verbose=2 dist/CodexTokenLedger.app
lipo -archs dist/CodexTokenLedger.app/Contents/MacOS/CodexTokenLedger
unzip -t dist/CodexTokenLedger-menu-bar-macOS.zip
```

Verified properties:

```text
Version: 2.1.0 (22)
Architectures: x86_64 arm64
Presentation: NSStatusItem + native NSMenu
Dashboard SwiftUI ScrollView: absent
SVG assets: 0
TiboWatch MIT license: bundled
Code signature: valid (ad-hoc)
ZIP integrity: no errors
```

Final artifacts:

```text
App: dist/CodexTokenLedger.app
Executable SHA-256: ff753541204ce6bd4d85d561574c2c17b8ee7ac1d1bf25381bff3079665fed56

ZIP: dist/CodexTokenLedger-menu-bar-macOS.zip
Bytes: 4447364
SHA-256: 2362075b217d76df24f5e63df672b2c441b5c715f1f740043ee18f21025834bb
```

Developer ID signing and Apple notarization remain public-distribution steps.
