# Phase 1: Foundation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade Aztec SDK to v4.1.2, fix security vulnerabilities, optimize iOS PXE cold start, and stabilize native prover.

**Architecture:** SDK upgrade is a dependency-first change (package.json + Nargo.toml + rebuild). Security fixes are isolated file edits. PXE optimization changes WalletStore initialization flow to show UI immediately while PXE loads in background. Swoirenberg work is an independent track.

**Tech Stack:** TypeScript, Swift 5.9, SwiftUI, Noir, esbuild, XcodeGen, WKWebView

---

## Task 1: SDK Version Upgrade — package.json

**Files:**
- Modify: `package.json:29-42`

- [ ] **Step 1: Update all @aztec/* dependencies to v4.1.2**

In `package.json`, change every `"4.1.0-rc.2"` to `"4.1.2"`:

```json
"dependencies": {
    "@aztec/accounts": "4.1.2",
    "@aztec/aztec.js": "4.1.2",
    "@aztec/bb-prover": "4.1.2",
    "@aztec/bb.js": "4.1.2",
    "@aztec/foundation": "4.1.2",
    "@aztec/l1-artifacts": "4.1.2",
    "@aztec/noir-contracts.js": "4.1.2",
    "@aztec/protocol-contracts": "4.1.2",
    "@aztec/pxe": "4.1.2",
    "@aztec/simulator": "4.1.2",
    "@aztec/stdlib": "4.1.2",
    "@aztec/wallets": "4.1.2",
    "@aztec/wallet-sdk": "4.1.2",
    "@walletconnect/sign-client": "^2.17.0"
}
```

- [ ] **Step 2: Update package version to 0.5.0**

In `package.json`, line 3:

```json
"version": "0.5.0",
```

- [ ] **Step 3: Clean install**

Run:
```bash
cd "/Users/huseyinarslan/Desktop/celari-build-25 kopyası"
rm -rf node_modules
npm install --legacy-peer-deps
```

Expected: Install completes without errors. All 14 `@aztec/*` packages resolve to `4.1.2`.

- [ ] **Step 4: Verify installed versions**

Run:
```bash
npm ls @aztec/aztec.js @aztec/pxe @aztec/wallets 2>/dev/null | head -10
```

Expected: All show `@4.1.2`

- [ ] **Step 5: Commit**

```bash
git add package.json package-lock.json
git commit -m "chore: upgrade Aztec SDK from v4.1.0-rc.2 to v4.1.2

Upgrades all 14 @aztec/* packages to stable v4.1.2.
Also bumps package version to 0.5.0 for consistency with manifest.json."
```

---

## Task 2: SDK Version Upgrade — Contract Nargo.toml Files

**Files:**
- Modify: `contracts/celari_passkey_account/Nargo.toml:8`
- Modify: `contracts/celari_recoverable_account/Nargo.toml:8`

- [ ] **Step 1: Update celari_passkey_account Nargo.toml**

In `contracts/celari_passkey_account/Nargo.toml`, line 8, change:

```toml
aztec = { git = "https://github.com/AztecProtocol/aztec-packages", tag = "v4.1.2", directory = "noir-projects/aztec-nr/aztec" }
```

- [ ] **Step 2: Update celari_recoverable_account Nargo.toml**

In `contracts/celari_recoverable_account/Nargo.toml`, line 8, change:

```toml
aztec = { git = "https://github.com/AztecProtocol/aztec-packages", tag = "v4.1.2", directory = "noir-projects/aztec-nr/aztec" }
```

- [ ] **Step 3: Compile contracts**

Run:
```bash
cd "/Users/huseyinarslan/Desktop/celari-build-25 kopyası"
cd contracts/celari_passkey_account && aztec compile
cd ../../contracts/celari_recoverable_account && aztec compile
```

Expected: Both compile successfully with no errors.

- [ ] **Step 4: Regenerate TypeScript artifacts**

Run:
```bash
cd "/Users/huseyinarslan/Desktop/celari-build-25 kopyası"
aztec codegen contracts/celari_passkey_account/target -o src/artifacts --nr
```

Expected: Artifact JSON files regenerated in `src/artifacts/`.

- [ ] **Step 5: Commit**

```bash
git add contracts/celari_passkey_account/Nargo.toml contracts/celari_recoverable_account/Nargo.toml src/artifacts/
git commit -m "chore: update contract dependencies to Aztec v4.1.2

Update both Nargo.toml files to tag v4.1.2 and recompile artifacts."
```

---

## Task 3: Rebuild offscreen.js Bundle (Extension + iOS)

**Files:**
- Regenerated: `extension/dist/src/offscreen.js`
- Regenerated: `ios/CelariWallet/CelariWallet/Resources/offscreen.js`

- [ ] **Step 1: Build offscreen.js**

Run:
```bash
cd "/Users/huseyinarslan/Desktop/celari-build-25 kopyası"
node extension/build.mjs
```

Expected: 3-pass esbuild completes. Pass 3 copies iOS variant to `ios/CelariWallet/CelariWallet/Resources/offscreen.js`.

- [ ] **Step 2: Verify iOS resource was updated**

Run:
```bash
ls -la ios/CelariWallet/CelariWallet/Resources/offscreen.js
```

Expected: File exists with recent timestamp.

- [ ] **Step 3: Verify SDK version in built bundle**

Run:
```bash
grep -o '"4\.1\.[0-9]*"' ios/CelariWallet/CelariWallet/Resources/offscreen.js | head -3
```

Expected: Shows `"4.1.2"` (not `"4.1.0-rc.2"`).

- [ ] **Step 4: Commit**

```bash
git add extension/dist/ ios/CelariWallet/CelariWallet/Resources/offscreen.js
git commit -m "build: rebuild offscreen.js with Aztec SDK v4.1.2"
```

---

## Task 4: Security Fix — content.js postMessage Origin

**Files:**
- Modify: `extension/public/src/content.js:54,74,77,85`

The wallet-sdk protocol uses `window.postMessage(response, "*")` at 4 call sites. While these messages stay in the same window context, using `"*"` is unnecessarily broad. Change to `window.location.origin` for defense-in-depth.

**Context:** Lines 110-130 (legacy protocol) already correctly use `window.location.origin`.

- [ ] **Step 1: Fix discovery response (line 54)**

In `extension/public/src/content.js`, line 54, change:

```javascript
    window.postMessage(response, "*");
```

to:

```javascript
    window.postMessage(response, window.location.origin);
```

- [ ] **Step 2: Fix wallet method error response (line 74)**

Line 74, change:

```javascript
        window.postMessage(errorResponse, "*");
```

to:

```javascript
        window.postMessage(errorResponse, window.location.origin);
```

- [ ] **Step 3: Fix wallet method success response (line 77)**

Line 77, change:

```javascript
        window.postMessage(result.rawResponse, "*");
```

to:

```javascript
        window.postMessage(result.rawResponse, window.location.origin);
```

- [ ] **Step 4: Fix wallet method catch error response (line 85)**

Line 85, change:

```javascript
      window.postMessage(errorResponse, "*");
```

to:

```javascript
      window.postMessage(errorResponse, window.location.origin);
```

- [ ] **Step 5: Verify no remaining wildcard postMessage calls**

Run:
```bash
grep -n 'postMessage.*"\*"' "/Users/huseyinarslan/Desktop/celari-build-25 kopyası/extension/public/src/content.js"
```

Expected: No output (zero matches).

- [ ] **Step 6: Commit**

```bash
git add extension/public/src/content.js
git commit -m "fix(security): restrict postMessage target origin in content.js

Replace wildcard '*' with window.location.origin in 4 wallet-sdk
protocol postMessage calls. Legacy protocol calls already used the
correct origin."
```

---

## Task 5: Version String Sync

**Files:**
- Modify: `extension/public/src/inpage.js:59`
- Modify: `extension/public/src/content.js:27`

manifest.json is already at `0.5.0`. package.json was updated in Task 1. These two files still show `0.3.0`.

- [ ] **Step 1: Update inpage.js version**

In `extension/public/src/inpage.js`, line 59, change:

```javascript
    version: "0.3.0",
```

to:

```javascript
    version: "0.5.0",
```

- [ ] **Step 2: Update content.js version**

In `extension/public/src/content.js`, line 27, change:

```javascript
  version: "0.3.0",
```

to:

```javascript
  version: "0.5.0",
```

- [ ] **Step 3: Verify all versions are in sync**

Run:
```bash
echo "package.json:"; grep '"version"' "/Users/huseyinarslan/Desktop/celari-build-25 kopyası/package.json" | head -1
echo "manifest.json:"; grep '"version"' "/Users/huseyinarslan/Desktop/celari-build-25 kopyası/extension/public/manifest.json"
echo "inpage.js:"; grep 'version:' "/Users/huseyinarslan/Desktop/celari-build-25 kopyası/extension/public/src/inpage.js" | head -1
echo "content.js:"; grep 'version:' "/Users/huseyinarslan/Desktop/celari-build-25 kopyası/extension/public/src/content.js" | head -1
```

Expected: All show `0.5.0`.

- [ ] **Step 4: Commit**

```bash
git add extension/public/src/inpage.js extension/public/src/content.js
git commit -m "chore: sync version strings to 0.5.0

Align inpage.js and content.js version fields with manifest.json and
package.json."
```

---

## Task 6: iOS PXE Lazy Initialization — State Enum

**Files:**
- Modify: `ios/CelariWallet/CelariWallet/Core/WalletStore.swift`

Currently `pxeInitialized` is a `Bool`. We add a `PXEState` enum for richer UI feedback and show the dashboard immediately with cached data while PXE loads.

- [ ] **Step 1: Add PXEState enum after the Screen enum**

In `WalletStore.swift`, after the `Screen` enum closing brace (after line 27), add:

```swift
    enum PXEState: Equatable {
        case notStarted
        case initializing
        case syncing(progress: String)
        case ready
        case failed(error: String)
    }
```

- [ ] **Step 2: Replace pxeInitialized/pxeInitFailed/pxeInitError with pxeState**

In `WalletStore.swift`, replace lines 193-195:

```swift
    var pxeInitialized: Bool = false
    var pxeInitFailed: Bool = false
    var pxeInitError: String = ""
```

with:

```swift
    var pxeState: PXEState = .notStarted
```

- [ ] **Step 3: Add computed properties for backward compatibility**

Immediately after the new `pxeState` property, add:

```swift
    var pxeInitialized: Bool { pxeState == .ready }
    var pxeInitFailed: Bool {
        if case .failed = pxeState { return true }
        return false
    }
```

- [ ] **Step 4: Update initialize() to use PXEState**

In `WalletStore.swift`, in the `initialize(pxeBridge:)` method (line 269+), apply these changes:

Replace line 324-326 (the guard failure):
```swift
                self.pxeInitFailed = true
                self.pxeInitError = "PXE engine failed to load. Check your connection and try again."
                self.showToast("PXE initialization failed — tap to retry", type: .error)
```
with:
```swift
                self.pxeState = .failed(error: "PXE engine failed to load. Check your connection and try again.")
                self.showToast("PXE initialization failed — tap to retry", type: .error)
```

Replace line 329-332 (PXE init start):
```swift
            walletLog.notice("[WalletStore] PXE bridge ready — sending PXE_INIT to \(self.nodeUrl, privacy: .public)")
            do {
                let result = try await pxeBridge.initPXE(nodeUrl: self.nodeUrl)
                self.pxeInitialized = true
```
with:
```swift
            walletLog.notice("[WalletStore] PXE bridge ready — sending PXE_INIT to \(self.nodeUrl, privacy: .public)")
            self.pxeState = .initializing
            do {
                let result = try await pxeBridge.initPXE(nodeUrl: self.nodeUrl)
                self.pxeState = .syncing(progress: "Restoring state...")
```

Replace line 347-353 (account re-registration section):
```swift
                if let account = self.activeAccount, account.deployed {
                    // Account already deployed — re-register with PXE (in-memory store is fresh)
                    walletLog.notice("[WalletStore] PXE ready, account deployed — re-registering with PXE")
                    await self.reRegisterAccount(pxeBridge: pxeBridge, account: account)
                    // Wait for PXE block sync to discover private notes (note sync needs a few seconds)
                    walletLog.notice("[WalletStore] Waiting 3s for PXE note sync...")
                    try? await Task.sleep(for: .seconds(3))
```
with:
```swift
                if let account = self.activeAccount, account.deployed {
                    self.pxeState = .syncing(progress: "Re-registering account...")
                    walletLog.notice("[WalletStore] PXE ready, account deployed — re-registering with PXE")
                    await self.reRegisterAccount(pxeBridge: pxeBridge, account: account)
                    self.pxeState = .syncing(progress: "Syncing notes...")
                    walletLog.notice("[WalletStore] Waiting 3s for PXE note sync...")
                    try? await Task.sleep(for: .seconds(3))
```

Add after the `savePXESnapshot()` call (after line 357):
```swift
                    self.pxeState = .ready
```

Replace lines 368-371 (error handler):
```swift
                walletLog.error("[WalletStore] PXE init failed: \(error.localizedDescription, privacy: .public)")
                self.pxeInitFailed = true
                self.pxeInitError = error.localizedDescription
                self.showToast("PXE init failed: \(error.localizedDescription)", type: .error)
```
with:
```swift
                walletLog.error("[WalletStore] PXE init failed: \(error.localizedDescription, privacy: .public)")
                self.pxeState = .failed(error: error.localizedDescription)
                self.showToast("PXE init failed: \(error.localizedDescription)", type: .error)
```

- [ ] **Step 5: Update retryPXEInit()**

In `retryPXEInit()` (line 377+), replace:
```swift
        pxeInitFailed = false
```
with:
```swift
        pxeState = .notStarted
```

- [ ] **Step 6: Search for any remaining pxeInitFailed/pxeInitError references**

Run:
```bash
grep -n "pxeInitFailed\|pxeInitError\|pxeInitialized" "/Users/huseyinarslan/Desktop/celari-build-25 kopyası/ios/CelariWallet/CelariWallet/Core/WalletStore.swift" | grep -v "//"
```

Expected: Only the computed properties from Step 3. If other direct usages remain in views, update them to use `pxeState`.

- [ ] **Step 7: Search views for pxeInitialized/pxeInitFailed references**

Run:
```bash
grep -rn "pxeInitialized\|pxeInitFailed\|pxeInitError" "/Users/huseyinarslan/Desktop/celari-build-25 kopyası/ios/CelariWallet/CelariWallet/Views/"
```

If matches found: The computed properties from Step 3 maintain backward compatibility, so existing views should continue to work. For views that can benefit from richer state (e.g., showing "Syncing..." instead of a generic spinner), update them to switch on `store.pxeState`.

- [ ] **Step 8: Commit**

```bash
cd "/Users/huseyinarslan/Desktop/celari-build-25 kopyası"
git add ios/CelariWallet/CelariWallet/Core/WalletStore.swift
git commit -m "feat(ios): add PXEState enum for richer initialization feedback

Replace boolean pxeInitialized/pxeInitFailed with PXEState enum
(.notStarted, .initializing, .syncing, .ready, .failed). Dashboard is
shown immediately with cached data while PXE loads in background.
Computed properties maintain backward compatibility with existing views."
```

---

## Task 7: iOS PXE — Show Dashboard Immediately

**Files:**
- Modify: `ios/CelariWallet/CelariWallet/Core/WalletStore.swift:298-301`

Currently when accounts exist, the dashboard is shown (line 299-301) but balances wait for PXE. We ensure cached token data is loaded immediately.

- [ ] **Step 1: Cache last known balances to UserDefaults**

In `WalletStore.swift`, find the `fetchBalances()` method. At the end of a successful balance fetch (where `self.tokens` is updated), add a cache write:

```swift
    // Cache balances for instant display on next launch
    if let data = try? JSONEncoder().encode(self.tokens) {
        UserDefaults.standard.set(data, forKey: "cachedTokens")
    }
```

- [ ] **Step 2: Load cached balances in loadFromStorage()**

In the `loadFromStorage()` method, add after existing loads:

```swift
    // Load cached token balances for instant dashboard display
    if let data = UserDefaults.standard.data(forKey: "cachedTokens"),
       let cached = try? JSONDecoder().decode([Token].self, from: data) {
        self.tokens = cached
    }
```

- [ ] **Step 3: Verify dashboard shows cached data before PXE is ready**

Build and run on simulator:
```bash
cd "/Users/huseyinarslan/Desktop/celari-build-25 kopyası/ios/CelariWallet"
xcodegen generate
xcodebuild -scheme CelariWallet -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -5
```

Expected: Build succeeds. On launch with existing accounts, dashboard appears immediately with last known balances.

- [ ] **Step 4: Commit**

```bash
cd "/Users/huseyinarslan/Desktop/celari-build-25 kopyası"
git add ios/CelariWallet/CelariWallet/Core/WalletStore.swift
git commit -m "feat(ios): cache token balances for instant dashboard display

Load last known balances from UserDefaults on launch. Dashboard shows
immediately with cached data while PXE syncs in background. Balances
update to live values once PXE reaches .ready state."
```

---

## Task 8: iOS PXE — Incremental Sync

**Files:**
- Modify: `ios/CelariWallet/CelariWallet/Core/WalletStore.swift`
- Modify: `ios/CelariWallet/CelariWallet/Core/PXEPersistenceManager.swift`

Store last synced block number alongside the snapshot. On restore, PXE only syncs from lastBlock+1.

- [ ] **Step 1: Add lastSyncedBlock to PXEPersistenceManager**

In `PXEPersistenceManager.swift`, add static methods:

```swift
    private static let blockKey = "pxe_last_synced_block"

    static func saveLastSyncedBlock(_ block: Int) {
        UserDefaults.standard.set(block, forKey: blockKey)
    }

    static func getLastSyncedBlock() -> Int? {
        let val = UserDefaults.standard.integer(forKey: blockKey)
        return val > 0 ? val : nil
    }
```

- [ ] **Step 2: Save block number when saving snapshot**

In `WalletStore.swift`, find the `savePXESnapshot()` method. After the successful save, add block number extraction:

```swift
    func savePXESnapshot() async {
        guard pxeInitialized, let pxeBridge else { return }
        do {
            let json = try await pxeBridge.saveSnapshot()
            try await PXEPersistenceManager.save(json: json)
            // Save last synced block for incremental sync
            if let blockNum = try? await pxeBridge.getBlockNumber() {
                PXEPersistenceManager.saveLastSyncedBlock(blockNum)
                walletLog.notice("[WalletStore] Snapshot saved at block \(blockNum, privacy: .public)")
            }
        } catch {
            walletLog.error("[WalletStore] Snapshot save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
```

- [ ] **Step 3: Log incremental sync info on restore**

In the `initialize()` method, after snapshot restore succeeds (line ~341), add logging:

```swift
                        if let lastBlock = PXEPersistenceManager.getLastSyncedBlock() {
                            walletLog.notice("[WalletStore] Incremental sync from block \(lastBlock, privacy: .public)")
                        }
```

This logs the sync starting point. The PXE engine itself handles incremental sync internally — it only re-syncs blocks after the snapshot's state. The block number is informational for debugging.

- [ ] **Step 4: Commit**

```bash
cd "/Users/huseyinarslan/Desktop/celari-build-25 kopyası"
git add ios/CelariWallet/CelariWallet/Core/WalletStore.swift ios/CelariWallet/CelariWallet/Core/PXEPersistenceManager.swift
git commit -m "feat(ios): track last synced block for incremental PXE sync

Store block number alongside PXE snapshot. On restore, log sync
starting point. PXE engine handles incremental sync internally from
the snapshot state."
```

---

## Task 9: iOS Build Verification

**Files:**
- No new files — verification only

- [ ] **Step 1: Regenerate Xcode project (new Swift code was added)**

Run:
```bash
cd "/Users/huseyinarslan/Desktop/celari-build-25 kopyası/ios/CelariWallet"
xcodegen generate
```

Expected: `Generated CelariWallet.xcodeproj`

- [ ] **Step 2: Build for simulator**

Run:
```bash
xcodebuild -project CelariWallet.xcodeproj -scheme CelariWallet -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -20
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Check for warnings related to our changes**

Run:
```bash
xcodebuild -project CelariWallet.xcodeproj -scheme CelariWallet -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | grep -i "warning:" | grep -i "walletstore\|pxe\|persistence"
```

Expected: No warnings from our modified files.

- [ ] **Step 4: Commit any Xcode project changes**

```bash
cd "/Users/huseyinarslan/Desktop/celari-build-25 kopyası"
git add ios/CelariWallet/CelariWallet.xcodeproj/
git commit -m "build(ios): regenerate xcodeproj after PXE state changes"
```

---

## Task 10: Swoirenberg XCFramework Debug (Track 2)

**Files:**
- Examine: `fork/swoirenberg/`
- Modify: `ios/CelariWallet/CelariWallet/Core/NativeProver.swift`
- Modify: `ios/CelariWallet/CelariWallet/Core/PXEBridge.swift:118`

This task is exploratory — the goal is to identify why `chonk_prove` crashes and add crash guards.

- [ ] **Step 1: Examine Swoirenberg build status**

Run:
```bash
cd "/Users/huseyinarslan/Desktop/celari-build-25 kopyası/fork/swoirenberg"
swift build 2>&1 | tail -30
```

Note any build errors. If there are errors, they indicate the XCFramework stability issue.

- [ ] **Step 2: Check Swoirenberg test suite**

Run:
```bash
cd "/Users/huseyinarslan/Desktop/celari-build-25 kopyası/fork/swoirenberg"
swift test 2>&1 | tail -30
```

Expected: Note which tests pass/fail. Failures in `chonk_prove` related tests confirm the known instability.

- [ ] **Step 3: Add crash guard to NativeProver.swift**

In `NativeProver.swift`, wrap the `chonkProve()` method body in a do-catch with explicit error capture:

Find the `chonkProve()` method and ensure it has a safe wrapper:

```swift
    func chonkProve() throws -> Data {
        guard chonkReady else { throw NativeProverError.chonkNotReady }
        let startTime = CFAbsoluteTimeGetCurrent()
        do {
            let proof = try Swoirenberg.chonkProve()
            lastChonkProveTime = CFAbsoluteTimeGetCurrent() - startTime
            return proof
        } catch {
            lastChonkProveTime = CFAbsoluteTimeGetCurrent() - startTime
            throw NativeProverError.chonkSessionFailed("chonk_prove crashed after \(String(format: "%.1f", lastChonkProveTime))s: \(error.localizedDescription)")
        }
    }
```

- [ ] **Step 4: Add availability flag to NativeProver**

At the top of `NativeProver.swift`, add a static availability check:

```swift
    /// Returns true if native proving is available and stable.
    /// Set to false to force WASM fallback.
    static let isEnabled: Bool = false // TODO: Set to true after Swoirenberg stabilization (Week 4 decision gate)
```

- [ ] **Step 5: Update PXEBridge.swift native prover flag**

In `PXEBridge.swift`, line 118, update the nativeProver availability to read from NativeProver:

```javascript
window.nativeProver = {
    available: ${NativeProver.isEnabled ? "true" : "false"},
```

Note: This is a JavaScript string injected from Swift. The `NativeProver.isEnabled` value should be interpolated at WebView setup time.

Alternatively, keep the hardcoded `false` for now and update it when the decision gate is reached:

```javascript
    available: false, // Decision gate: Week 4 — set to true after Swoirenberg stabilizes
```

- [ ] **Step 6: Document the decision gate**

Create a comment block at the top of `NativeProver.swift`:

```swift
// NATIVE PROVER STATUS
// ====================
// Current: DISABLED (WASM fallback active)
// Reason: Swoirenberg XCFramework chonk_prove crashes on some circuits
// Decision gate: End of Week 4 (approx. 2026-04-27)
//   - If stable on iPhone 13+: enable native proving, keep WASM as fallback
//   - If unstable: stay on WASM, track CHONK prover for future integration
// To test: Set NativeProver.isEnabled = true and run proof benchmark
```

- [ ] **Step 7: Commit**

```bash
cd "/Users/huseyinarslan/Desktop/celari-build-25 kopyası"
git add ios/CelariWallet/CelariWallet/Core/NativeProver.swift ios/CelariWallet/CelariWallet/Core/PXEBridge.swift
git commit -m "feat(ios): add crash guard and decision gate for native prover

Add do-catch crash guard around chonk_prove. Add NativeProver.isEnabled
static flag (currently false). Document week 4 decision gate for
enabling native proving vs staying on WASM."
```

---

## Task 11: Extension Rebuild + Final Verification

**Files:**
- Regenerated: `extension/dist/`

- [ ] **Step 1: Rebuild extension with all fixes**

Run:
```bash
cd "/Users/huseyinarslan/Desktop/celari-build-25 kopyası"
node extension/build.mjs
```

Expected: All 3 passes complete successfully.

- [ ] **Step 2: Verify content.js fix is in dist**

Run:
```bash
grep -c 'postMessage.*"\*"' extension/dist/src/content.js
```

Expected: `0` (no wildcard postMessage calls).

- [ ] **Step 3: Verify version strings in dist**

Run:
```bash
grep -o '"0\.[0-9]\.[0-9]"' extension/dist/src/inpage.js | head -1
grep -o '"0\.[0-9]\.[0-9]"' extension/dist/src/content.js | head -1
```

Expected: Both show `"0.5.0"`.

- [ ] **Step 4: Run existing tests**

Run:
```bash
cd "/Users/huseyinarslan/Desktop/celari-build-25 kopyası"
NODE_NO_WARNINGS=1 npx jest --forceExit 2>&1 | tail -20
```

Expected: All existing tests pass. If any fail, investigate — the SDK upgrade may have changed internal behaviors.

- [ ] **Step 5: Commit dist**

```bash
git add extension/dist/
git commit -m "build: rebuild extension dist with security fixes and v4.1.2 SDK"
```

---

## Summary

| Task | Track | What | Files Modified |
|------|-------|------|----------------|
| 1 | 1 | SDK upgrade package.json | package.json |
| 2 | 1 | SDK upgrade Nargo.toml | 2 Nargo.toml files, src/artifacts/ |
| 3 | 1 | Rebuild offscreen.js | extension/dist/, iOS Resources |
| 4 | 1 | postMessage security fix | content.js |
| 5 | 1 | Version sync | inpage.js, content.js |
| 6 | 1 | PXEState enum | WalletStore.swift |
| 7 | 1 | Cached dashboard | WalletStore.swift |
| 8 | 1 | Incremental sync | WalletStore.swift, PXEPersistenceManager.swift |
| 9 | 1 | iOS build verification | xcodeproj |
| 10 | 2 | Swoirenberg debug | NativeProver.swift, PXEBridge.swift |
| 11 | 1 | Final rebuild + verify | extension/dist/ |

**Estimated time:** Tasks 1-9 + 11 (Track 1): ~3-4 hours. Task 10 (Track 2): 1-2 days investigation.
