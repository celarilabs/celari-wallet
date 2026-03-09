# Celari Wallet iOS — Architecture Fixes Design

**Date**: 2026-02-24
**Status**: Approved
**Scope**: 4 remaining post-audit architectural tasks

## Context

Post-audit code fixes (22/22 findings) are complete and building cleanly. Four architectural tasks remain before TestFlight readiness. NavigationStack refactor deferred — current manual routing works.

## Priority Order

1. WKURLSchemeHandler (security — remove private API)
2. Deploy hang debug + fix (functionality blocker)
3. Bundle optimization (performance)
4. Dynamic Type (accessibility)

---

## 1. WKURLSchemeHandler — `celari://` Custom Scheme

**Problem**: `allowFileAccessFromFileURLs` is a private WebKit API. App Store review may reject.

**Solution**: Implement `WKURLSchemeHandler` with custom `celari://` scheme.

### New file: `CelariSchemeHandler.swift`

- Conforms to `WKURLSchemeHandler`
- `webView(_:start:)`: Parse filename from URL path → read from `Bundle.main` → set MIME type → respond
- `webView(_:stop:)`: No-op (all responses are synchronous from bundle)
- `mimeType(for:)`: Extension-based mapping (`.js` → `text/javascript`, `.wasm` → `application/wasm`, `.html` → `text/html`, `.json` → `application/json`)

### PXEBridge.swift changes

- Remove: `config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")`
- Add: `config.setURLSchemeHandler(CelariSchemeHandler(), forURLScheme: "celari")`
- Change: `loadFileURL(htmlURL, ...)` → `load(URLRequest(url: URL(string: "celari://pxe-bridge.html")!))`

### pxe-bridge.html change

- `<script type="module" src="offscreen.js">` → `<script type="module" src="celari://offscreen.js">`

### WASM resolution

`import.meta.url` becomes `celari://offscreen.js` → `new URL("acvm_js_bg.wasm", import.meta.url)` resolves to `celari://acvm_js_bg.wasm` → SchemeHandler serves from bundle.

---

## 2. Deploy Hang — Debug + Fix

**Problem**: Account deploy never completes on iOS. PXE init succeeds but `deployAccountClientSide()` hangs. JS logs not visible — can't determine which step fails.

### Phase 1: Granular logging

Add timestamp logs to `deployAccountClientSide()` and split `setupSponsoredFPC()`:

```
Step 1: wallet.createAccount()
Step 2a: SponsoredFPCContract artifact import
Step 2b: getContractInstanceFromInstantiationParams() (WASM op)
Step 2c: walletInstance.registerContract()
Step 3: manager.getDeployMethod()
Step 4: deployMethod.send()
Step 5: sentTx.getTxHash()
Step 6: sentTx.wait()
```

Each step logs start/end/duration via `console.log()` → captured by Swift `jsConsole` handler → visible in Xcode Console with `[PXE-JS:log]` prefix.

### Phase 2: Debug with Xcode + Safari Inspector

- Xcode Console: filter `PXE` to see all step timings
- Safari Web Inspector: Develop → Device → WKWebView for live debugging
- Network tab: verify WASM fetch responses (status, size, content-type)

### Phase 3: Fix based on findings

| Hang point | Likely cause | Fix |
|---|---|---|
| `wallet.createAccount()` | Contract artifact serialization | Lazy-load artifact, store minimal data |
| `setupSponsoredFPC()` | WASM op in `getContractInstanceFromInstantiationParams` | May resolve after WKURLSchemeHandler fix (correct WASM loading) |
| `deployMethod.send()` | BB proving (~140s/proof, main thread) | Expected — extend timeout, show progress |
| `sentTx.wait()` | Node connection or block inclusion | Network debug, timeout increase |

**Key dependency**: WKURLSchemeHandler (task 1) may fix WASM loading issues that cause the hang. Debug after task 1 is complete.

---

## 3. Bundle Optimization (69MB JS)

**Problem**: `offscreen.js` is 69MB — slow parse time on WKWebView first load.

### Phase 1: Gzip serving via SchemeHandler

- Build time: compress `offscreen.js` → `offscreen.js.gz` (post-esbuild script)
- Runtime: `CelariSchemeHandler` checks for `.gz` variant first, serves with `Content-Encoding: gzip`
- WKWebView (Safari engine) auto-decompresses
- Expected: 69MB → ~12-15MB served size

### Phase 2: Tree-shaking improvements

- `build.mjs` Pass 3: add explicit `treeShaking: true`
- Review `sideEffects` in Aztec SDK packages
- Conditional exclude unused modules (e.g., WalletConnect if not needed on iOS)

### Phase 3: Lazy import (future)

- Contract imports already use `await import()` — good
- Core Aztec SDK is the bulk — limited tree-shake potential
- Consider splitting PXE init into light bootstrap + heavy load phases

---

## 4. Dynamic Type Support (Body Text Only)

**Problem**: All fonts are fixed-size. Accessibility requirement for App Store.

**Scope**: Only readable content fonts. Heading and mono fonts stay fixed (design identity).

### CelariTheme.swift changes

```swift
// Dynamic Type enabled:
static let body      = Font.custom("Outfit-Regular", size: 13, relativeTo: .body)
static let bodySmall = Font.custom("Outfit-Regular", size: 11, relativeTo: .footnote)
static let accent    = Font.custom("TenorSans-Regular", size: 12, relativeTo: .body)

// Fixed (unchanged):
// heading, headingSmall, subheading, title — PoiretOne
// mono, monoSmall, monoLabel, monoTiny — IBMPlexMono
// balance — PoiretOne
```

### Overflow protection

- `.dynamicTypeSize(...:.xxxLarge)` on toast messages and long descriptions
- Mono/heading fixed → no layout breakage risk

### Out of scope

- `@ScaledMetric` spacing — not needed, grid layout is stable
- Mono/heading fonts — design integrity preserved

---

## Execution Order

```
Task 1: WKURLSchemeHandler ──→ Task 2: Deploy debug ──→ Task 3: Bundle optimization
                                                              │
Task 4: Dynamic Type (independent, can parallel with 2 or 3) ┘
```

Task 2 depends on Task 1 (scheme change affects WASM loading).
Task 3 builds on Task 1 (gzip serving uses SchemeHandler).
Task 4 is independent.
