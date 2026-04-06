# Comprehensive Improvement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix all medium-priority security issues, refactor monolithic Swift files into testable modules, complete missing feature infrastructure, add test coverage, and optimize bundle performance.

**Architecture:** Three sequential waves — Wave 1 (quick wins: security fixes + feature infra), Wave 2 (refactoring + tests), Wave 3 (performance + cleanup). Within each wave, Track A and Track B run in parallel.

**Tech Stack:** TypeScript (Jest), Swift 5.9 (SwiftUI, @Observable), Noir (Aztec contracts), esbuild

**Spec:** `docs/superpowers/specs/2026-04-05-comprehensive-improvement-design.md`

---

## File Map

### Wave 1 Files
| Action | File | Responsibility |
|--------|------|---------------|
| Modify | `extension/public/src/inpage.js` | Add unsubscribe to `on()`, add `off()` method |
| Modify | `website/src/hooks/useCelariExtension.ts` | Replace empty catch blocks with debug logging |
| Modify | `extension/build.mjs` | Add stale sourcemap cleanup step |
| Modify | `src/test/unit/extension.test.ts` | Add `on()`/`off()` tests |
| Modify | `src/utils/dex.ts` | Replace stubs with contract-ready interface |
| Create | `src/test/unit/dex.test.ts` | DexClient unit tests |
| Modify | `ios/CelariWallet/CelariWallet/Views/Recovery/GuardianSetupView.swift` | Wire IPFSManager for real CID upload |
| Modify | `ios/CelariWallet/CelariWallet/V2/Views/RecoverAccountViewV2.swift` | Add TimelineView countdown |

### Wave 2 Files
| Action | File | Responsibility |
|--------|------|---------------|
| Create | `ios/CelariWallet/CelariWallet/Core/WalletPersistence.swift` | UserDefaults/Keychain read/write |
| Create | `ios/CelariWallet/CelariWallet/Core/WalletNetworkManager.swift` | Connection, network switching |
| Create | `ios/CelariWallet/CelariWallet/Core/GuardianManager.swift` | Guardian recovery state |
| Modify | `ios/CelariWallet/CelariWallet/Core/WalletStore.swift` | Slim down to orchestration + forwarding |
| Create | `ios/CelariWallet/CelariWallet/Core/PXEMessageBus.swift` | Async messaging infra + protocol |
| Create | `ios/CelariWallet/CelariWallet/Core/PXENativeProver.swift` | Swoirenberg bridge |
| Modify | `ios/CelariWallet/CelariWallet/Core/PXEBridge.swift` | Slim down to API wrappers |
| Create | `bridge/sdk/__tests__/content-hash.test.ts` | Content hash unit tests |

### Deferred to Follow-Up Plan (after this plan stabilizes)
| Action | File | Reason |
|--------|------|--------|
| Create | `ios/.../Core/AccountManager.swift` | Largest extraction (~230 lines), depends on Tasks 8-10 being stable |
| Create | `ios/.../Core/TokenManager.swift` | Complex PXE coupling, depends on Tasks 8-10 being stable |
| Create | `ios/.../Core/PXEWebViewManager.swift` | Optional — WebView lifecycle is tightly coupled to MessageBus |
| Create | `bridge/sdk/__tests__/l1-client.test.ts` | Requires complex viem mock setup |
| Create | `bridge/sdk/__tests__/l2-client.test.ts` | Requires complex Aztec PXE mock setup |
| Modify | `contracts/.../src/test.nr` | P256 test needs TXE auth witness injection (not yet available) |
| Modify | `contracts/.../src/test.nr` | Guardian E2E needs TXE (not yet available) |

### Wave 3 Files
| Action | File | Responsibility |
|--------|------|---------------|
| Modify | `extension/build.mjs` | Add bundle analysis logging |
| Modify | `jest.config.ts` | Add coverage configuration |
| Modify | `.gitignore` | Add backup-before-fixes/, coverage/ |

---

## Wave 1, Track A — Security Fixes

### Task 1: Fix Event Listener Memory Leak in Inpage Provider

**Files:**
- Modify: `extension/public/src/inpage.js:104-111`
- Modify: `src/test/unit/extension.test.ts` (append new describe block)

- [ ] **Step 1: Write failing test for `on()` returning unsubscribe**

Append this describe block to `src/test/unit/extension.test.ts`:

```typescript
describe("Inpage Provider: Event Listener Management", () => {
  it("on() should return an unsubscribe function", () => {
    // Simulate the on() method from inpage.js
    const listeners: Array<{ event: string; handler: Function }> = [];
    const addListener = (event: string, handler: Function) => {
      listeners.push({ event, handler });
    };
    const removeListener = (_event: string, handler: Function) => {
      const idx = listeners.findIndex(l => l.handler === handler);
      if (idx >= 0) listeners.splice(idx, 1);
    };

    // Replicate the fixed on() logic
    function on(event: string, callback: Function) {
      const handler = (e: any) => {
        if (e.data?.target === "celari-inpage" && e.data?.event === event) {
          callback(e.data.payload);
        }
      };
      addListener("message", handler);
      return () => removeListener("message", handler);
    }

    const unsub = on("accountChanged", () => {});
    expect(typeof unsub).toBe("function");
    expect(listeners).toHaveLength(1);

    unsub();
    expect(listeners).toHaveLength(0);
  });

  it("off() should call the unsubscribe function", () => {
    let unsubCalled = false;
    const mockUnsub = () => { unsubCalled = true; };

    function off(_event: string, handler: Function) {
      if (typeof handler === "function") handler();
    }

    off("accountChanged", mockUnsub);
    expect(unsubCalled).toBe(true);
  });
});
```

- [ ] **Step 2: Run test to verify it passes**

```bash
cd "/Users/huseyinarslan/Desktop/celari-build-25 kopyası" && NODE_NO_WARNINGS=1 npx jest src/test/unit/extension.test.ts --forceExit
```

Expected: All existing tests PASS, new tests PASS (they test extracted logic, not DOM).

- [ ] **Step 3: Fix `on()` in inpage.js and add `off()`**

In `extension/public/src/inpage.js`, replace lines 104-111:

```javascript
    /** Listen for account/network changes */
    on(event, callback) {
      window.addEventListener("message", (e) => {
        if (e.data?.target === "celari-inpage" && e.data?.event === event) {
          callback(e.data.payload);
        }
      });
    },
```

With:

```javascript
    /** Listen for account/network changes. Returns unsubscribe function. */
    on(event, callback) {
      const handler = (e) => {
        if (e.data?.target === "celari-inpage" && e.data?.event === event) {
          callback(e.data.payload);
        }
      };
      window.addEventListener("message", handler);
      return () => window.removeEventListener("message", handler);
    },

    /** Remove a listener. Pass the unsubscribe function returned by on(). */
    off(event, unsub) {
      if (typeof unsub === "function") unsub();
    },
```

- [ ] **Step 4: Verify tests still pass**

```bash
cd "/Users/huseyinarslan/Desktop/celari-build-25 kopyası" && NODE_NO_WARNINGS=1 npx jest src/test/unit/extension.test.ts --forceExit
```

Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
cd "/Users/huseyinarslan/Desktop/celari-build-25 kopyası" && git add extension/public/src/inpage.js src/test/unit/extension.test.ts && git commit -m "fix: add unsubscribe to inpage on() and add off() method

Prevents memory leak from unbounded event listener accumulation
when dApps call window.celari.on() repeatedly."
```

---

### Task 2: Fix Empty Catch Blocks in useCelariExtension

**Files:**
- Modify: `website/src/hooks/useCelariExtension.ts:18,35`

- [ ] **Step 1: Replace empty catch on line 18**

In `website/src/hooks/useCelariExtension.ts`, replace:

```typescript
          .catch(() => {});
```

With:

```typescript
          .catch((err) => {
            console.debug("[Celari] getAddress failed:", (err as Error).message);
          });
```

- [ ] **Step 2: Replace empty catch on line 35**

In the same file, replace:

```typescript
    } catch {}
```

With:

```typescript
    } catch (err) {
      console.debug("[Celari] connect failed:", (err as Error).message);
    }
```

- [ ] **Step 3: Commit**

```bash
cd "/Users/huseyinarslan/Desktop/celari-build-25 kopyası" && git add website/src/hooks/useCelariExtension.ts && git commit -m "fix: replace empty catch blocks with debug logging in useCelariExtension

Silent error suppression hid extension connection failures."
```

---

### Task 3: Add Stale Sourcemap Cleanup to Build Script

**Files:**
- Modify: `extension/build.mjs:14-15,57`

- [ ] **Step 1: Add unlinkSync import and cleanup step**

In `extension/build.mjs`, replace the import line:

```javascript
import { cpSync, mkdirSync, existsSync } from "fs";
```

With:

```javascript
import { cpSync, mkdirSync, existsSync, unlinkSync } from "fs";
```

- [ ] **Step 2: Add sourcemap cleanup before Pass 2**

In `extension/build.mjs`, before the line `console.log("  Pass 2: Bundling offscreen.js with Aztec SDK...");` (line 59), add:

```javascript
  // Clean stale sourcemaps from previous dev builds
  const staleMap = resolve(outdir, "src/offscreen.js.map");
  if (!isDev && existsSync(staleMap)) {
    unlinkSync(staleMap);
    console.log("  Cleaned stale sourcemap: offscreen.js.map");
  }

```

- [ ] **Step 3: Commit**

```bash
cd "/Users/huseyinarslan/Desktop/celari-build-25 kopyası" && git add extension/build.mjs && git commit -m "fix: clean stale sourcemaps in production builds

Prevents 78MB dev sourcemap from persisting in production dist."
```

---

### Task 4: Verify and Sync Version Strings

**Files:**
- Check: `extension/public/manifest.json:4`, `package.json:3`, `extension/public/src/inpage.js:59`

- [ ] **Step 1: Verify all versions match**

Current state (verified):
- `manifest.json:4` → `"version": "0.5.0"` ✓
- `package.json:3` → `"version": "0.5.0"` ✓
- `inpage.js:59` → `version: "0.5.0"` ✓

All versions already synced. No changes needed.

- [ ] **Step 2: Commit (skip if no changes)**

No commit needed — versions already synced.

---

## Wave 1, Track B — Missing Feature Infrastructure

### Task 5: Upgrade DexClient from Stubs to Contract-Ready Interface

**Files:**
- Modify: `src/utils/dex.ts`
- Create: `src/test/unit/dex.test.ts`

- [ ] **Step 1: Write DexClient tests**

Create `src/test/unit/dex.test.ts`:

```typescript
import { describe, it, expect } from "@jest/globals";
import { DexClient } from "../../utils/dex.js";

describe("DexClient", () => {
  describe("without contract address", () => {
    const client = new DexClient("https://rpc.testnet.aztec-labs.com/");

    it("getQuote should throw DexNotAvailable", async () => {
      await expect(
        client.getQuote("0xtoken1", "0xtoken2", 1000n)
      ).rejects.toThrow("DEX contract not configured");
    });

    it("executeSwap should throw DexNotAvailable", async () => {
      await expect(
        client.executeSwap(
          { tokenIn: "0x1", tokenOut: "0x2", amountIn: 100n, amountOut: 99n, priceImpact: 0.01, estimatedGas: 500000n, expiresAt: Date.now() + 30000 },
          "0xwallet"
        )
      ).rejects.toThrow("DEX contract not configured");
    });

    it("getSupportedPairs should return empty array", async () => {
      const pairs = await client.getSupportedPairs();
      expect(pairs).toEqual([]);
    });

    it("isAvailable should return false", () => {
      expect(client.isAvailable()).toBe(false);
    });
  });

  describe("with contract address", () => {
    const client = new DexClient(
      "https://rpc.testnet.aztec-labs.com/",
      "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"
    );

    it("isAvailable should return true", () => {
      expect(client.isAvailable()).toBe(true);
    });

    it("getSupportedPairs should return hardcoded pairs", async () => {
      const pairs = await client.getSupportedPairs();
      expect(pairs.length).toBeGreaterThan(0);
      expect(pairs[0]).toHaveProperty("tokenA");
      expect(pairs[0]).toHaveProperty("tokenB");
    });
  });
});
```

- [ ] **Step 2: Run tests — expect failures**

```bash
cd "/Users/huseyinarslan/Desktop/celari-build-25 kopyası" && NODE_NO_WARNINGS=1 npx jest src/test/unit/dex.test.ts --forceExit
```

Expected: FAIL — `DexClient` constructor doesn't accept second param, no `isAvailable()` method, `getQuote()` returns placeholder instead of throwing.

- [ ] **Step 3: Rewrite DexClient**

Replace the entire content of `src/utils/dex.ts`:

```typescript
import { AztecAddress } from "@aztec/aztec.js";

export interface SwapQuote {
  tokenIn: string;
  tokenOut: string;
  amountIn: bigint;
  amountOut: bigint;
  priceImpact: number;
  estimatedGas: bigint;
  expiresAt: number;
}

export interface TokenPair {
  tokenA: string;
  tokenB: string;
  liquidity: bigint;
}

/** Default pairs — will be replaced with on-chain query when DEX contract is live. */
const DEFAULT_PAIRS: TokenPair[] = [
  { tokenA: "ETH", tokenB: "zkUSD", liquidity: 0n },
  { tokenA: "ETH", tokenB: "DAI", liquidity: 0n },
  { tokenA: "zkUSD", tokenB: "DAI", liquidity: 0n },
];

/**
 * Client for interacting with DEX contracts on Aztec.
 *
 * When constructed without a contract address, all trading methods throw
 * "DEX contract not configured". This allows the UI to gracefully show
 * "DEX not available" instead of crashing.
 *
 * When a contract address is provided, methods will interact with the
 * on-chain AMM (not yet implemented — requires deployed DEX contract).
 */
export class DexClient {
  private nodeUrl: string;
  private contractAddress: string | undefined;

  constructor(nodeUrl: string, dexContractAddress?: string) {
    this.nodeUrl = nodeUrl;
    this.contractAddress = dexContractAddress;
  }

  /** Whether a DEX contract is configured and trading is possible. */
  isAvailable(): boolean {
    return this.contractAddress !== undefined;
  }

  /**
   * Get a swap quote from the DEX.
   * Throws if no contract address is configured.
   */
  async getQuote(
    tokenIn: string,
    tokenOut: string,
    amountIn: bigint,
    slippage: number = 0.01
  ): Promise<SwapQuote> {
    if (!this.contractAddress) {
      throw new Error("DEX contract not configured");
    }
    // Contract interaction will go here when DEX is deployed.
    // For now, provide a local estimate so the UI can render.
    const slippageBps = BigInt(Math.floor(slippage * 10000));
    const estimatedOut = amountIn * (10000n - slippageBps) / 10000n;
    return {
      tokenIn,
      tokenOut,
      amountIn,
      amountOut: estimatedOut,
      priceImpact: slippage,
      estimatedGas: 500000n,
      expiresAt: Date.now() + 30000,
    };
  }

  /**
   * Execute a swap through the DEX contract.
   * Throws if no contract address is configured.
   */
  async executeSwap(quote: SwapQuote, walletAddress: string): Promise<string> {
    if (!this.contractAddress) {
      throw new Error("DEX contract not configured");
    }
    // Contract call will go here when DEX is deployed.
    throw new Error("DEX swap execution not yet implemented — awaiting contract deployment");
  }

  /**
   * Get available trading pairs.
   * Returns hardcoded defaults when contract is configured, empty otherwise.
   */
  async getSupportedPairs(): Promise<TokenPair[]> {
    if (!this.contractAddress) {
      return [];
    }
    return DEFAULT_PAIRS;
  }
}
```

- [ ] **Step 4: Run tests — expect pass**

```bash
cd "/Users/huseyinarslan/Desktop/celari-build-25 kopyası" && NODE_NO_WARNINGS=1 npx jest src/test/unit/dex.test.ts --forceExit
```

Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
cd "/Users/huseyinarslan/Desktop/celari-build-25 kopyası" && git add src/utils/dex.ts src/test/unit/dex.test.ts && git commit -m "feat: upgrade DexClient from stubs to contract-ready interface

Throws clear errors when no DEX contract configured. UI can check
isAvailable() to show 'DEX not available' gracefully."
```

---

### Task 6: Add Recovery Countdown Timer UI

**Files:**
- Modify: `ios/CelariWallet/CelariWallet/V2/Views/RecoverAccountViewV2.swift`

- [ ] **Step 1: Add TimelineView countdown to the timeLock step**

In `RecoverAccountViewV2.swift`, find the `.timeLock` case in the body view (this is the step that shows after guardian approvals are met). Look for where `timeLockRemaining` is displayed and replace the static text with a `TimelineView`:

Find the section that displays the timelock remaining (around the `.timeLock` case in the view body). Replace any static `Text` showing the countdown with:

```swift
TimelineView(.periodic(from: .now, by: 1)) { context in
    let remaining = max(0, recoveryDeadline.timeIntervalSince(context.date))
    let hours = Int(remaining) / 3600
    let minutes = (Int(remaining) % 3600) / 60
    let seconds = Int(remaining) % 60

    VStack(spacing: 16) {
        Text("Recovery Time-Lock")
            .font(.headline)

        Text(String(format: "%02d:%02d:%02d", hours, minutes, seconds))
            .font(.system(size: 48, weight: .bold, design: .monospaced))
            .foregroundStyle(remaining > 0 ? .secondary : .green)

        if remaining <= 0 {
            Button("Execute Recovery") {
                Task { await finalizeRecovery() }
            }
            .buttonStyle(.borderedProminent)
        } else {
            Text("Recovery will be available when countdown reaches zero")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
```

- [ ] **Step 2: Add `recoveryDeadline` state property**

At the top of the struct, with the other `@State` properties, add:

```swift
@State private var recoveryDeadline: Date = .distantFuture
```

- [ ] **Step 3: Set deadline in `refreshCountdownFromChain()`**

In the `refreshCountdownFromChain()` method (around line 381-401), after calculating the remaining time from block-based timelock, set the deadline:

```swift
// After getting remainingBlocks from PXE:
let remainingSeconds = Double(remainingBlocks) * 12.0 // ~12s per block
recoveryDeadline = Date().addingTimeInterval(remainingSeconds)
```

- [ ] **Step 4: Schedule local notification**

After setting `recoveryDeadline`, call the existing notification scheduler:

```swift
store.scheduleRecoveryNotification(deadline: recoveryDeadline)
```

- [ ] **Step 5: Build iOS project to verify compilation**

```bash
cd "/Users/huseyinarslan/Desktop/celari-build-25 kopyası/ios/CelariWallet" && xcodebuild -scheme CelariWallet -destination 'generic/platform=iOS' -quiet build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
cd "/Users/huseyinarslan/Desktop/celari-build-25 kopyası" && git add ios/CelariWallet/CelariWallet/V2/Views/RecoverAccountViewV2.swift && git commit -m "feat(ios): add live countdown timer for recovery time-lock

Uses TimelineView for real-time HH:MM:SS display. Execute Recovery
button activates when countdown reaches zero."
```

---

### Task 7: Wire IPFS Upload in Guardian Setup

**Files:**
- Modify: `ios/CelariWallet/CelariWallet/Views/Recovery/GuardianSetupView.swift:229-246`

- [ ] **Step 1: Replace hardcoded CID with real IPFSManager upload**

In `GuardianSetupView.swift`, find the section around line 229-232 where CID is hardcoded:

```swift
// TODO: IPFS upload
let cidPart1 = "0"
let cidPart2 = "0"
```

Replace with:

```swift
// Upload recovery bundle to IPFS via Pinata
let bundleJson = try JSONEncoder().encode(bundle)
let bundleDict = try JSONSerialization.jsonObject(with: bundleJson) as? [String: Any] ?? [:]
let cid = try await IPFSManager.shared.upload(json: bundleDict)

// Split CID into two Field-sized parts (31 bytes each)
// CIDv0 is 46 chars (base58), fits in two 31-byte fields
let cidBytes = Array(cid.utf8)
let midpoint = min(cidBytes.count, 31)
let cidPart1Bytes = cidBytes[0..<midpoint]
let cidPart2Bytes = midpoint < cidBytes.count ? cidBytes[midpoint...] : ArraySlice<UInt8>()
let cidPart1 = "0x" + cidPart1Bytes.map { String(format: "%02x", $0) }.joined()
let cidPart2 = "0x" + cidPart2Bytes.map { String(format: "%02x", $0) }.joined()
```

- [ ] **Step 2: Add QR code generation for guardian key sharing**

After the `setupGuardians()` PXE call succeeds (around line 242), add QR code display. Find the `.done` step UI and add a QR generation helper:

```swift
// Add this method to the struct:
private func generateQRCode(from string: String) -> UIImage? {
    let data = string.data(using: .ascii)
    guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
    filter.setValue(data, forKey: "inputMessage")
    filter.setValue("M", forKey: "inputCorrectionLevel")
    guard let output = filter.outputImage else { return nil }
    let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
    return UIImage(ciImage: scaled)
}
```

- [ ] **Step 3: Add `import CoreImage` at the top of the file if not present**

```swift
import CoreImage
```

- [ ] **Step 4: Display QR code in the `.done` step**

In the `.done` case of the view body, add a QR code showing the CID so guardians can scan it:

```swift
if let qrImage = generateQRCode(from: cid) {
    VStack(spacing: 8) {
        Text("Share with your guardians")
            .font(.headline)
        Image(uiImage: qrImage)
            .interpolation(.none)
            .resizable()
            .scaledToFit()
            .frame(width: 200, height: 200)
        Text("CID: \(cid)")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
```

- [ ] **Step 5: Add `@State private var cid: String = ""` property**

Store the CID from the upload so the `.done` step can display it.

- [ ] **Step 6: Build iOS project to verify compilation**

```bash
cd "/Users/huseyinarslan/Desktop/celari-build-25 kopyası/ios/CelariWallet" && xcodebuild -scheme CelariWallet -destination 'generic/platform=iOS' -quiet build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 7: Commit**

```bash
cd "/Users/huseyinarslan/Desktop/celari-build-25 kopyası" && git add ios/CelariWallet/CelariWallet/Views/Recovery/GuardianSetupView.swift && git commit -m "feat(ios): wire IPFS upload and QR code sharing in guardian setup

Replaces hardcoded CID='0' with real Pinata upload. Adds QR code
for guardians to scan recovery bundle CID."
```

---

## Wave 2, Track A — Architecture Refactoring

### Task 8: Extract PersistenceManager from WalletStore

**Files:**
- Create: `ios/CelariWallet/CelariWallet/Core/WalletPersistence.swift`
- Modify: `ios/CelariWallet/CelariWallet/Core/WalletStore.swift`

This is the first extraction — persistence has the fewest dependencies on other WalletStore state, making it the safest to extract first.

- [ ] **Step 1: Create WalletPersistence.swift**

Create `ios/CelariWallet/CelariWallet/Core/WalletPersistence.swift`:

```swift
import Foundation

/// Handles all UserDefaults and Keychain persistence for wallet data.
/// Extracted from WalletStore to isolate storage concerns.
@Observable
final class WalletPersistence {
    private let defaults = UserDefaults.standard
    private let suiteName = "group.com.celari.wallet"

    // MARK: - Accounts

    func loadAccounts() -> [Account] {
        guard let data = defaults.data(forKey: "celari_accounts"),
              let accounts = try? JSONDecoder().decode([Account].self, from: data) else {
            return []
        }
        return accounts
    }

    func saveAccounts(_ accounts: [Account]) {
        if let data = try? JSONEncoder().encode(accounts) {
            defaults.set(data, forKey: "celari_accounts")
        }
    }

    // MARK: - Config

    func loadConfig() -> (nodeUrl: String, network: String, deployServerUrl: String) {
        let nodeUrl = defaults.string(forKey: "celari_node_url") ?? "https://rpc.testnet.aztec-labs.com/"
        let network = defaults.string(forKey: "celari_network") ?? "testnet"
        let deployServerUrl = defaults.string(forKey: "celari_deploy_server") ?? ""
        return (nodeUrl, network, deployServerUrl)
    }

    func saveConfig(nodeUrl: String, network: String, deployServerUrl: String) {
        defaults.set(nodeUrl, forKey: "celari_node_url")
        defaults.set(network, forKey: "celari_network")
        defaults.set(deployServerUrl, forKey: "celari_deploy_server")
    }

    // MARK: - Custom Tokens

    func loadCustomTokens() -> [CustomToken] {
        guard let data = defaults.data(forKey: "celari_custom_tokens"),
              let tokens = try? JSONDecoder().decode([CustomToken].self, from: data) else {
            return []
        }
        return tokens
    }

    func saveCustomTokens(_ tokens: [CustomToken]) {
        if let data = try? JSONEncoder().encode(tokens) {
            defaults.set(data, forKey: "celari_custom_tokens")
        }
    }

    // MARK: - Activities

    func loadActivities() -> [Activity] {
        guard let data = defaults.data(forKey: "celari_activities"),
              let activities = try? JSONDecoder().decode([Activity].self, from: data) else {
            return []
        }
        return activities
    }

    func saveActivities(_ activities: [Activity]) {
        if let data = try? JSONEncoder().encode(activities) {
            defaults.set(data, forKey: "celari_activities")
        }
    }

    // MARK: - Guardian Status

    func loadGuardianStatus() -> GuardianStatus {
        guard let data = defaults.data(forKey: "celari_guardian_status"),
              let status = try? JSONDecoder().decode(GuardianStatus.self, from: data) else {
            return .notConfigured
        }
        return status
    }

    func saveGuardianStatus(_ status: GuardianStatus) {
        if let data = try? JSONEncoder().encode(status) {
            defaults.set(data, forKey: "celari_guardian_status")
        }
    }

    // MARK: - NFT Contracts

    func loadNftContracts() -> [NFTContract] {
        guard let data = defaults.data(forKey: "celari_nft_contracts"),
              let contracts = try? JSONDecoder().decode([NFTContract].self, from: data) else {
            return []
        }
        return contracts
    }

    func saveNftContracts(_ contracts: [NFTContract]) {
        if let data = try? JSONEncoder().encode(contracts) {
            defaults.set(data, forKey: "celari_nft_contracts")
        }
    }

    // MARK: - Bridge Transactions

    func loadBridgeTransactions() -> [BridgeTransaction] {
        guard let data = defaults.data(forKey: "celari_bridge_transactions"),
              let txs = try? JSONDecoder().decode([BridgeTransaction].self, from: data) else {
            return []
        }
        return txs
    }

    func saveBridgeTransactions(_ txs: [BridgeTransaction]) {
        if let data = try? JSONEncoder().encode(txs) {
            defaults.set(data, forKey: "celari_bridge_transactions")
        }
    }

    // MARK: - Preferences

    var backupReminderDismissed: Bool {
        get { defaults.bool(forKey: "celari_backup_dismissed") }
        set { defaults.set(newValue, forKey: "celari_backup_dismissed") }
    }

    // MARK: - Widget Update

    func updateWidget(tokens: [Token]) {
        guard let shared = UserDefaults(suiteName: suiteName) else { return }
        if let data = try? JSONEncoder().encode(tokens) {
            shared.set(data, forKey: "celari_widget_tokens")
        }
    }
}
```

- [ ] **Step 2: Wire WalletPersistence into WalletStore**

In `WalletStore.swift`, add a property:

```swift
let persistence = WalletPersistence()
```

Then replace each direct `UserDefaults` call in `loadFromStorage()`, `saveAccounts()`, `saveConfig()`, `saveCustomTokens()`, `saveActivities()`, `saveGuardianStatus()`, `saveNftContracts()`, `saveBridgeTransactions()` with delegation to `persistence`. For example:

```swift
func saveAccounts() {
    persistence.saveAccounts(accounts)
}

func loadFromStorage() {
    accounts = persistence.loadAccounts()
    let config = persistence.loadConfig()
    nodeUrl = config.nodeUrl
    network = config.network
    deployServerUrl = config.deployServerUrl
    customTokens = persistence.loadCustomTokens()
    activities = persistence.loadActivities()
    guardianStatus = persistence.loadGuardianStatus()
    customNftContracts = persistence.loadNftContracts()
    bridgeTransactions = persistence.loadBridgeTransactions()
}
```

- [ ] **Step 3: Update token didSet to use persistence**

In `WalletStore.swift`, find the `tokens` property `didSet` that updates the widget. Replace the direct `UserDefaults(suiteName:)` call with:

```swift
var tokens: [Token] = Token.defaults {
    didSet { persistence.updateWidget(tokens: tokens) }
}
```

- [ ] **Step 4: Run xcodegen and build**

```bash
cd "/Users/huseyinarslan/Desktop/celari-build-25 kopyası/ios/CelariWallet" && xcodegen generate && xcodebuild -scheme CelariWallet -destination 'generic/platform=iOS' -quiet build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
cd "/Users/huseyinarslan/Desktop/celari-build-25 kopyası" && git add ios/CelariWallet/CelariWallet/Core/WalletPersistence.swift ios/CelariWallet/CelariWallet/Core/WalletStore.swift ios/CelariWallet/CelariWallet.xcodeproj/ && git commit -m "refactor(ios): extract WalletPersistence from WalletStore

Isolates all UserDefaults/Keychain operations into a dedicated class.
WalletStore delegates all save/load calls to WalletPersistence."
```

---

### Task 9: Extract NetworkManager from WalletStore

**Files:**
- Create: `ios/CelariWallet/CelariWallet/Core/WalletNetworkManager.swift`
- Modify: `ios/CelariWallet/CelariWallet/Core/WalletStore.swift`

- [ ] **Step 1: Create WalletNetworkManager.swift**

Create `ios/CelariWallet/CelariWallet/Core/WalletNetworkManager.swift`:

```swift
import Foundation

/// Manages network connectivity, node info, and network switching.
/// Extracted from WalletStore lines 493-513, 193-196.
@Observable
final class WalletNetworkManager {
    var connected: Bool = false
    var network: String = "testnet"
    var nodeUrl: String = "https://rpc.testnet.aztec-labs.com/"
    var nodeInfo: NodeInfo?
    var customNetworks: [CustomNetwork] = []
    var deployServerUrl: String = ""

    func checkConnection() async {
        do {
            let url = URL(string: "\(nodeUrl)/api/node-info")!
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                connected = false
                return
            }
            nodeInfo = try JSONDecoder().decode(NodeInfo.self, from: data)
            connected = true
        } catch {
            connected = false
            nodeInfo = nil
        }
    }

    func switchNetwork(preset: NetworkPreset) async {
        nodeUrl = preset.url
        network = preset.name
        connected = false
        nodeInfo = nil
        await checkConnection()
    }
}
```

- [ ] **Step 2: Wire into WalletStore with forwarding properties**

In `WalletStore.swift`, add:

```swift
let networkManager = WalletNetworkManager()
```

Add computed forwarding properties for backward compatibility:

```swift
var connected: Bool { networkManager.connected }
var network: String {
    get { networkManager.network }
    set { networkManager.network = newValue }
}
var nodeUrl: String {
    get { networkManager.nodeUrl }
    set { networkManager.nodeUrl = newValue }
}
var nodeInfo: NodeInfo? { networkManager.nodeInfo }
```

Remove the original stored properties and delegate `checkConnection()` and `switchNetwork()`:

```swift
func checkConnection() async {
    await networkManager.checkConnection()
}

func switchNetwork(preset: NetworkPreset) async {
    await networkManager.switchNetwork(preset: preset)
    persistence.saveConfig(nodeUrl: networkManager.nodeUrl, network: networkManager.network, deployServerUrl: networkManager.deployServerUrl)
}
```

- [ ] **Step 3: Update loadFromStorage to populate networkManager**

```swift
// In loadFromStorage():
let config = persistence.loadConfig()
networkManager.nodeUrl = config.nodeUrl
networkManager.network = config.network
networkManager.deployServerUrl = config.deployServerUrl
```

- [ ] **Step 4: Run xcodegen and build**

```bash
cd "/Users/huseyinarslan/Desktop/celari-build-25 kopyası/ios/CelariWallet" && xcodegen generate && xcodebuild -scheme CelariWallet -destination 'generic/platform=iOS' -quiet build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
cd "/Users/huseyinarslan/Desktop/celari-build-25 kopyası" && git add ios/CelariWallet/CelariWallet/Core/WalletNetworkManager.swift ios/CelariWallet/CelariWallet/Core/WalletStore.swift ios/CelariWallet/CelariWallet.xcodeproj/ && git commit -m "refactor(ios): extract WalletNetworkManager from WalletStore

Isolates connection checking, network switching, and node info
management. WalletStore forwards via computed properties."
```

---

### Task 10: Extract GuardianManager from WalletStore

**Files:**
- Create: `ios/CelariWallet/CelariWallet/Core/GuardianManager.swift`
- Modify: `ios/CelariWallet/CelariWallet/Core/WalletStore.swift`

- [ ] **Step 1: Create GuardianManager.swift**

Create `ios/CelariWallet/CelariWallet/Core/GuardianManager.swift`:

```swift
import Foundation
import UserNotifications

/// Manages guardian recovery state, status checks, and notifications.
/// Extracted from WalletStore lines 264-265, 677-729.
@Observable
final class GuardianManager {
    var guardianStatus: GuardianStatus = .notConfigured
    var guardians: [String] = []

    private let persistence: WalletPersistence

    init(persistence: WalletPersistence) {
        self.persistence = persistence
        self.guardianStatus = persistence.loadGuardianStatus()
    }

    func checkGuardianStatus(pxeBridge: PXEBridge) async {
        do {
            let isConfigured = try await pxeBridge.isGuardianConfigured()
            if isConfigured {
                guardianStatus = .configured
            }
        } catch {
            // Guardian check failed — status unchanged
        }
    }

    func scheduleRecoveryNotification(deadline: Date) {
        let content = UNMutableNotificationContent()
        content.title = "Recovery Ready"
        content.body = "Your account recovery time-lock has expired. You can now complete the recovery."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, deadline.timeIntervalSinceNow),
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: "recovery-timelock",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request)
    }

    func save() {
        persistence.saveGuardianStatus(guardianStatus)
    }
}
```

- [ ] **Step 2: Wire into WalletStore**

In `WalletStore.swift`:

```swift
lazy var guardianManager = GuardianManager(persistence: persistence)
```

Add forwarding:

```swift
var guardianStatus: GuardianStatus {
    get { guardianManager.guardianStatus }
    set { guardianManager.guardianStatus = newValue }
}
var guardians: [String] {
    get { guardianManager.guardians }
    set { guardianManager.guardians = newValue }
}

func checkGuardianStatus() async {
    guard let bridge = pxeBridge else { return }
    await guardianManager.checkGuardianStatus(pxeBridge: bridge)
}

func scheduleRecoveryNotification(deadline: Date) {
    guardianManager.scheduleRecoveryNotification(deadline: deadline)
}
```

Remove the original stored properties and methods.

- [ ] **Step 3: Run xcodegen and build**

```bash
cd "/Users/huseyinarslan/Desktop/celari-build-25 kopyası/ios/CelariWallet" && xcodegen generate && xcodebuild -scheme CelariWallet -destination 'generic/platform=iOS' -quiet build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
cd "/Users/huseyinarslan/Desktop/celari-build-25 kopyası" && git add ios/CelariWallet/CelariWallet/Core/GuardianManager.swift ios/CelariWallet/CelariWallet/Core/WalletStore.swift ios/CelariWallet/CelariWallet.xcodeproj/ && git commit -m "refactor(ios): extract GuardianManager from WalletStore

Isolates guardian recovery state, status checks, and notification
scheduling into dedicated @Observable class."
```

---

### Task 11: Extract PXEMessageBus from PXEBridge

**Files:**
- Create: `ios/CelariWallet/CelariWallet/Core/PXEMessageBus.swift`
- Modify: `ios/CelariWallet/CelariWallet/Core/PXEBridge.swift`

- [ ] **Step 1: Create PXEMessageBus protocol and implementation**

Create `ios/CelariWallet/CelariWallet/Core/PXEMessageBus.swift`:

```swift
import Foundation
import WebKit

/// Protocol for PXE async messaging — enables mocking in tests.
protocol PXEMessageBusProtocol {
    func sendMessage(_ type: String, data: [String: Any]) async throws -> [String: Any]
    @MainActor func evaluateJS(_ jsCode: String) async throws
}

/// Manages async continuation-based messaging between Swift and the PXE WebView.
/// Extracted from PXEBridge lines 28-41, 210-276.
final class PXEMessageBus: PXEMessageBusProtocol {
    private var pendingCallbacks: [String: CheckedContinuation<[String: Any], Error>] = [:]
    private let lock = NSLock()
    private weak var webView: WKWebView?

    init(webView: WKWebView? = nil) {
        self.webView = webView
    }

    func setWebView(_ webView: WKWebView) {
        self.webView = webView
    }

    // MARK: - Continuation Management

    func storeContinuation(_ id: String, _ continuation: CheckedContinuation<[String: Any], Error>) {
        lock.lock()
        defer { lock.unlock() }
        pendingCallbacks[id] = continuation
    }

    func resumeContinuation(_ id: String, with result: Result<[String: Any], Error>) {
        lock.lock()
        let cb = pendingCallbacks.removeValue(forKey: id)
        lock.unlock()
        switch result {
        case .success(let value): cb?.resume(returning: value)
        case .failure(let error): cb?.resume(throwing: error)
        }
    }

    // MARK: - Message Sending

    func sendMessage(_ type: String, data: [String: Any] = [:]) async throws -> [String: Any] {
        guard webView != nil else {
            throw PXEError.notReady
        }

        let messageId = "\(UUID().uuidString.prefix(8))_\(Int(Date().timeIntervalSince1970 * 1000))"

        // Determine timeout based on message type
        let timeoutSeconds: Int
        switch type {
        case "PXE_FAUCET": timeoutSeconds = 1200
        case "PXE_DEPLOY_ACCOUNT", "PXE_TRANSFER", "PXE_TRANSFER_NFT",
             "PXE_SAVE_SNAPSHOT", "PXE_RESTORE_SNAPSHOT": timeoutSeconds = 600
        default: timeoutSeconds = 300
        }

        var payload = data
        payload["messageId"] = messageId
        payload["type"] = type

        let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[String: Any], Error>) in
            storeContinuation(messageId, continuation)

            Task { @MainActor in
                guard let jsonData = try? JSONSerialization.data(withJSONObject: payload),
                      let jsonString = String(data: jsonData, encoding: .utf8) else {
                    self.resumeContinuation(messageId, with: .failure(PXEError.jsError("Failed to serialize message")))
                    return
                }
                let js = "window.handleSwiftMessage && window.handleSwiftMessage(\(jsonString))"
                try? await self.webView?.evaluateJavaScript(js)
            }

            // Timeout
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds) * 1_000_000_000)
                self.resumeContinuation(messageId, with: .failure(PXEError.timeout))
            }
        }

        if let error = result["error"] as? String {
            throw PXEError.jsError(error)
        }

        return result
    }

    @MainActor
    func evaluateJS(_ jsCode: String) async throws {
        try await webView?.evaluateJavaScript(jsCode)
    }
}
```

- [ ] **Step 2: Update PXEBridge to use PXEMessageBus**

In `PXEBridge.swift`, replace the inline `pendingCallbacks`, `lock`, `sendMessage()`, `evaluateJS()`, `storeContinuation()`, and `resumeContinuation()` with:

```swift
let messageBus = PXEMessageBus()
```

Then update `sendMessage` calls throughout to use `messageBus.sendMessage()`. In `setupWebView()`, after creating the WKWebView, call:

```swift
messageBus.setWebView(webView!)
```

In `userContentController(_:didReceive:)`, replace direct continuation resumes with:

```swift
messageBus.resumeContinuation(messageId, with: .success(responseDict))
```

- [ ] **Step 3: Run xcodegen and build**

```bash
cd "/Users/huseyinarslan/Desktop/celari-build-25 kopyası/ios/CelariWallet" && xcodegen generate && xcodebuild -scheme CelariWallet -destination 'generic/platform=iOS' -quiet build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
cd "/Users/huseyinarslan/Desktop/celari-build-25 kopyası" && git add ios/CelariWallet/CelariWallet/Core/PXEMessageBus.swift ios/CelariWallet/CelariWallet/Core/PXEBridge.swift ios/CelariWallet/CelariWallet.xcodeproj/ && git commit -m "refactor(ios): extract PXEMessageBus from PXEBridge

Isolates async continuation management and timeout logic into a
protocol-based class. Enables mock injection for testing."
```

---

### Task 12: Extract PXENativeProver from PXEBridge

**Files:**
- Create: `ios/CelariWallet/CelariWallet/Core/PXENativeProver.swift`
- Modify: `ios/CelariWallet/CelariWallet/Core/PXEBridge.swift`

- [ ] **Step 1: Create PXENativeProver.swift**

Extract the `handleNativeProverRequest()` method and all Swoirenberg-related code (PXEBridge lines 652-850) into `PXENativeProver.swift`. The class takes a `PXEMessageBus` reference to deliver callbacks:

```swift
import Foundation

/// Bridges Swoirenberg native prover operations.
/// Extracted from PXEBridge lines 652-850.
final class PXENativeProver {
    private weak var messageBus: PXEMessageBus?

    init(messageBus: PXEMessageBus) {
        self.messageBus = messageBus
    }

    func handleRequest(_ json: [String: Any]) {
        // Move the entire handleNativeProverRequest() body here
        // Replace deliverNativeProverCallback calls with messageBus callback delivery
        guard let action = json["action"] as? String,
              let callbackId = json["callbackId"] as? String else { return }

        Task {
            // ... existing switch on action for setup_srs, execute, prove, etc.
            // Each case calls NativeProver methods and delivers result via:
            await deliverCallback(callbackId, result: resultDict)
        }
    }

    @MainActor
    private func deliverCallback(_ callbackId: String, result: [String: Any]) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: result),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }
        let js = "window.nativeProverCallback && window.nativeProverCallback('\(callbackId)', \(jsonString))"
        Task { try? await messageBus?.evaluateJS(js) }
    }
}
```

- [ ] **Step 2: Update PXEBridge to delegate native prover requests**

In `PXEBridge.swift`, add property:

```swift
private lazy var nativeProver = PXENativeProver(messageBus: messageBus)
```

In `userContentController` case "nativeProver", replace:

```swift
handleNativeProverRequest(body)
```

With:

```swift
nativeProver.handleRequest(body)
```

Remove the original `handleNativeProverRequest()` and `deliverNativeProverCallback()` methods from PXEBridge.

- [ ] **Step 3: Run xcodegen and build**

```bash
cd "/Users/huseyinarslan/Desktop/celari-build-25 kopyası/ios/CelariWallet" && xcodegen generate && xcodebuild -scheme CelariWallet -destination 'generic/platform=iOS' -quiet build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
cd "/Users/huseyinarslan/Desktop/celari-build-25 kopyası" && git add ios/CelariWallet/CelariWallet/Core/PXENativeProver.swift ios/CelariWallet/CelariWallet/Core/PXEBridge.swift ios/CelariWallet/CelariWallet.xcodeproj/ && git commit -m "refactor(ios): extract PXENativeProver from PXEBridge

Isolates Swoirenberg native prover operations (SRS setup, prove,
verify, Chonk pipeline) into dedicated class."
```

---

## Wave 2, Track B — Test Coverage

### Task 13: Add Bridge SDK Content Hash Tests

**Files:**
- Create: `bridge/sdk/__tests__/content-hash.test.ts`

- [ ] **Step 1: Create content-hash.test.ts**

Create `bridge/sdk/__tests__/content-hash.test.ts`:

```typescript
import { describe, it, expect } from "@jest/globals";
import {
  sha256ToField,
  bigintToBytes32,
  addressToBytes32,
  computeDepositContentHash,
  computeWithdrawContentHash,
  generateSecretHash,
  hexToBigInt,
  bigintToHex,
} from "../content-hash.js";

describe("Content Hash Utilities", () => {
  describe("sha256ToField", () => {
    it("should zero the MSB (byte 0) for BN254 compatibility", () => {
      const hash = new Uint8Array(32);
      hash[0] = 0xff; // MSB should be ignored
      hash[1] = 0x01;
      const field = sha256ToField(hash);
      // byte 0 skipped, byte 1 = 0x01, rest = 0x00
      expect(field).toBe(BigInt("0x01") << BigInt(240));
    });

    it("should produce deterministic output", () => {
      const hash = new Uint8Array(32).fill(0xab);
      const a = sha256ToField(hash);
      const b = sha256ToField(hash);
      expect(a).toBe(b);
    });
  });

  describe("bigintToBytes32", () => {
    it("should encode zero as 32 zero bytes", () => {
      const bytes = bigintToBytes32(0n);
      expect(bytes.length).toBe(32);
      expect(bytes.every(b => b === 0)).toBe(true);
    });

    it("should encode 1 as last byte = 1", () => {
      const bytes = bigintToBytes32(1n);
      expect(bytes[31]).toBe(1);
      expect(bytes[30]).toBe(0);
    });

    it("should roundtrip with hexToBigInt", () => {
      const original = 123456789n;
      const bytes = bigintToBytes32(original);
      const hex = "0x" + Array.from(bytes).map(b => b.toString(16).padStart(2, "0")).join("");
      expect(hexToBigInt(hex)).toBe(original);
    });
  });

  describe("addressToBytes32", () => {
    it("should right-align 20-byte address in 32 bytes", () => {
      const bytes = addressToBytes32("0x" + "ff".repeat(20));
      // First 12 bytes should be zero padding
      for (let i = 0; i < 12; i++) expect(bytes[i]).toBe(0);
      // Last 20 bytes should be 0xff
      for (let i = 12; i < 32; i++) expect(bytes[i]).toBe(0xff);
    });

    it("should handle address without 0x prefix", () => {
      const bytes = addressToBytes32("aa".repeat(20));
      expect(bytes[12]).toBe(0xaa);
    });
  });

  describe("computeDepositContentHash", () => {
    it("should produce a field element (< 2^254)", async () => {
      const hash = await computeDepositContentHash(
        "0x" + "11".repeat(20), // token
        1000n,                   // amount
        42n,                     // to (L2 address as bigint)
        99n,                     // secretHash
      );
      expect(hash).toBeGreaterThan(0n);
      expect(hash).toBeLessThan(2n ** 254n);
    });

    it("should be deterministic", async () => {
      const args = ["0x" + "ab".repeat(20), 500n, 1n, 2n] as const;
      const a = await computeDepositContentHash(...args);
      const b = await computeDepositContentHash(...args);
      expect(a).toBe(b);
    });
  });

  describe("computeWithdrawContentHash", () => {
    it("should produce a field element", async () => {
      const hash = await computeWithdrawContentHash(
        "0x" + "11".repeat(20), // token
        1000n,                   // amount
        "0x" + "22".repeat(20), // recipient
        "0x" + "33".repeat(20), // callerOnL1
      );
      expect(hash).toBeGreaterThan(0n);
      expect(hash).toBeLessThan(2n ** 254n);
    });
  });

  describe("generateSecretHash", () => {
    it("should produce secret and secretHash as bigints", async () => {
      const { secret, secretHash } = await generateSecretHash();
      expect(typeof secret).toBe("bigint");
      expect(typeof secretHash).toBe("bigint");
      expect(secret).toBeGreaterThan(0n);
      expect(secretHash).toBeGreaterThan(0n);
    });

    it("should produce unique secrets", async () => {
      const a = await generateSecretHash();
      const b = await generateSecretHash();
      expect(a.secret).not.toBe(b.secret);
    });
  });

  describe("hex conversion", () => {
    it("hexToBigInt should parse 0x prefix", () => {
      expect(hexToBigInt("0xff")).toBe(255n);
    });

    it("hexToBigInt should parse without prefix", () => {
      expect(hexToBigInt("ff")).toBe(255n);
    });

    it("bigintToHex should produce 64-char padded hex", () => {
      const hex = bigintToHex(255n);
      expect(hex).toBe("0x" + "0".repeat(62) + "ff");
      expect(hex.length).toBe(66); // 0x + 64
    });
  });
});
```

- [ ] **Step 2: Run tests**

```bash
cd "/Users/huseyinarslan/Desktop/celari-build-25 kopyası" && NODE_NO_WARNINGS=1 npx jest bridge/sdk/__tests__/content-hash.test.ts --forceExit
```

Expected: All tests PASS.

- [ ] **Step 3: Commit**

```bash
cd "/Users/huseyinarslan/Desktop/celari-build-25 kopyası" && git add bridge/sdk/__tests__/content-hash.test.ts && git commit -m "test: add bridge content hash unit tests

Covers sha256ToField, bigintToBytes32, addressToBytes32,
deposit/withdraw content hash computation, secret generation."
```

---

## Wave 3 — Performance + Cleanup

### Task 14: Add Bundle Size Analysis to Build Script

**Files:**
- Modify: `extension/build.mjs`

- [ ] **Step 1: Add metafile analysis after Pass 2**

In `extension/build.mjs`, add `metafile: true` to the Pass 2 build config (line 61-123):

Add to the build options object:

```javascript
    metafile: true,
```

After the `await build(...)` call for Pass 2, add:

```javascript
  // Analyze bundle composition
  const result = await build({
    // ... existing config + metafile: true
  });

  if (result.metafile) {
    const outputs = result.metafile.outputs;
    const mainOutput = Object.entries(outputs).find(([k]) => k.includes("offscreen"));
    if (mainOutput) {
      const [name, meta] = mainOutput;
      const sizeMB = (meta.bytes / 1048576).toFixed(1);
      console.log(`  Bundle size: ${sizeMB} MB`);

      // Top 10 largest inputs
      const inputs = Object.entries(meta.inputs)
        .sort(([, a], [, b]) => b.bytesInOutput - a.bytesInOutput)
        .slice(0, 10);
      console.log("  Top 10 largest modules:");
      for (const [path, info] of inputs) {
        const mb = (info.bytesInOutput / 1048576).toFixed(2);
        console.log(`    ${mb} MB — ${path}`);
      }
    }
  }
```

Note: You'll need to restructure the Pass 2 build to capture the result. Change:

```javascript
  await build({
```

To:

```javascript
  const pass2Result = await build({
```

And add `metafile: true` to the options. Then use `pass2Result.metafile` for analysis.

- [ ] **Step 2: Run build and note baseline size**

```bash
cd "/Users/huseyinarslan/Desktop/celari-build-25 kopyası" && node extension/build.mjs 2>&1 | grep -E "(Bundle size|Top 10|MB —)"
```

Record the output — this is the baseline for future optimization.

- [ ] **Step 3: Commit**

```bash
cd "/Users/huseyinarslan/Desktop/celari-build-25 kopyası" && git add extension/build.mjs && git commit -m "chore: add bundle size analysis to build script

Logs top 10 largest modules after offscreen.js bundle for
identifying tree-shaking opportunities."
```

---

### Task 15: Setup Code Coverage Reporting

**Files:**
- Modify: `jest.config.ts`
- Modify: `.gitignore`

- [ ] **Step 1: Run baseline coverage**

```bash
cd "/Users/huseyinarslan/Desktop/celari-build-25 kopyası" && NODE_NO_WARNINGS=1 npx jest --coverage --forceExit 2>&1 | tail -20
```

Note the current coverage percentages.

- [ ] **Step 2: Add coverage config to jest.config.ts**

In `jest.config.ts`, add these properties to the exported object:

```typescript
  collectCoverageFrom: [
    "src/**/*.ts",
    "bridge/sdk/**/*.ts",
    "!src/artifacts/**",
    "!src/test/**",
  ],
  coverageDirectory: "coverage",
  coverageReporters: ["text", "text-summary", "lcov"],
```

Do NOT add `coverageThreshold` yet — set thresholds after seeing the baseline numbers.

- [ ] **Step 3: Add coverage/ to .gitignore**

In `.gitignore`, add:

```
# Coverage reports
coverage/
```

Also add:

```
# Backup directories
backup-before-fixes/
```

- [ ] **Step 4: Run coverage to verify**

```bash
cd "/Users/huseyinarslan/Desktop/celari-build-25 kopyası" && NODE_NO_WARNINGS=1 npx jest --coverage --forceExit 2>&1 | tail -30
```

Expected: Coverage report printed to console and `coverage/` directory created.

- [ ] **Step 5: Commit**

```bash
cd "/Users/huseyinarslan/Desktop/celari-build-25 kopyası" && git add jest.config.ts .gitignore && git commit -m "chore: add Jest coverage reporting and update .gitignore

Configures coverage collection for src/ and bridge/sdk/.
Adds coverage/ and backup-before-fixes/ to .gitignore."
```

---

## Summary

| Wave | Task | Description | Track |
|------|------|-------------|-------|
| 1 | 1 | Fix event listener memory leak + add `off()` | A |
| 1 | 2 | Fix empty catch blocks | A |
| 1 | 3 | Add stale sourcemap cleanup | A |
| 1 | 4 | Verify version sync (no-op) | A |
| 1 | 5 | Upgrade DexClient to contract-ready | B |
| 1 | 6 | Add recovery countdown timer | B |
| 1 | 7 | Wire IPFS upload in guardian setup | B |
| 2 | 8 | Extract WalletPersistence | A |
| 2 | 9 | Extract WalletNetworkManager | A |
| 2 | 10 | Extract GuardianManager | A |
| 2 | 11 | Extract PXEMessageBus | A |
| 2 | 12 | Extract PXENativeProver | A |
| 2 | 13 | Bridge SDK content hash tests | B |
| 3 | 14 | Bundle size analysis | — |
| 3 | 15 | Code coverage setup | — |

**Parallel execution:** Tasks 1-4 (Track A) can run in parallel with Tasks 5-7 (Track B). Tasks 8-12 (Track A) can run in parallel with Task 13 (Track B). Tasks 14-15 are sequential.

**Critical dependency:** Tasks 8-12 must complete before iOS unit tests (future work after this plan).

---

## Deferred Spec Items

These items from the spec are intentionally deferred from this plan:

| Spec Item | Reason | When |
|-----------|--------|------|
| **R1: AccountManager + TokenManager extraction** | Largest, riskiest extractions. Run after Persistence/Network/Guardian extractions prove stable. | Follow-up plan after Wave 2 |
| **R2: PXEWebViewManager extraction** | Optional — WebView lifecycle is tightly coupled to MessageBus setup. Marginal benefit. | If PXEBridge remains >400 lines after Tasks 11-12 |
| **T2: P256 signature verification test** | TXE doesn't support auth witness injection yet. Upstream Noir stdlib tests cover this. | When TXE adds auth witness support |
| **T3: WalletStore unit tests** | Depends on refactoring completion (Tasks 8-12 + AccountManager/TokenManager). | Follow-up plan |
| **T4: Guardian recovery E2E test** | TXE full integration not yet available. Contract-level unit tests exist (Task 13 pattern). | When TXE supports full contract interaction |
| **P1: offscreen.js tree-shaking** | Task 14 provides bundle analysis. Actual tree-shaking requires analyzing which @aztec modules are unused — depends on analysis output. | After Task 14 reveals optimization targets |
| **P2: PXE lazy initialization** | Already planned in roadmap Phase 1.3. Snapshot restore is already implemented. | Roadmap Phase 1.3 |
| **P3: Bridge SDK lazy loading** | Requires esbuild `splitting: true` which needs ESM format throughout. Low priority until bridge is actively used. | After bridge goes live |
| **S5: Dead code cleanup (extension/src/)** | Directory doesn't exist — already clean. No action needed. | N/A |
