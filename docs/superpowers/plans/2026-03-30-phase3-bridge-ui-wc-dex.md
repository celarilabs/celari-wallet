# Phase 3: Bridge UI + WalletConnect + DEX Layer — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add L1↔L2 bridge UI, WalletConnect deep linking, tab navigation expansion, and DEX interaction layer.

**Architecture:** WalletConnect v2 infrastructure is 95% complete (PXEBridge, offscreen.js, views all exist). Bridge UI is new — leverages existing bridge-client.ts SDK. DEX layer is new TypeScript + offscreen.js handlers.

**Tech Stack:** Swift 5.9, SwiftUI, TypeScript, esbuild

---

## Task 1: WalletStore Bridge State

**Files:**
- Modify: `ios/CelariWallet/CelariWallet/Core/WalletStore.swift`

Add bridge transaction tracking to WalletStore.

- [ ] **Step 1: Add BridgeTransaction model and state**

Add after GuardianStatus enum:

```swift
    struct BridgeTransaction: Codable, Identifiable, Equatable {
        let id: UUID
        let type: BridgeType
        let token: String
        let amount: String
        var status: BridgeStatus
        let l1TxHash: String?
        var l2TxHash: String?
        let timestamp: Date

        enum BridgeType: String, Codable { case deposit, withdraw }
        enum BridgeStatus: String, Codable { case pending, l1Confirmed, l2Claimed, failed }
    }
```

Add property:
```swift
    var bridgeTransactions: [BridgeTransaction] = []
```

- [ ] **Step 2: Add bridge persistence**

In `loadFromStorage()`:
```swift
        if let data = UserDefaults.standard.data(forKey: "bridgeTransactions"),
           let txs = try? JSONDecoder().decode([BridgeTransaction].self, from: data) {
            self.bridgeTransactions = txs
        }
```

Add save method:
```swift
    func saveBridgeTransactions() {
        if let data = try? JSONEncoder().encode(bridgeTransactions) {
            UserDefaults.standard.set(data, forKey: "bridgeTransactions")
        }
    }
```

- [ ] **Step 3: Commit**

```bash
git add ios/CelariWallet/CelariWallet/Core/WalletStore.swift
git commit -m "feat(ios): add bridge transaction state management"
```

---

## Task 2: BridgeViewV2 — L1↔L2 Bridge UI

**Files:**
- Create: `ios/CelariWallet/CelariWallet/V2/Views/BridgeViewV2.swift`

- [ ] **Step 1: Create BridgeViewV2.swift**

```swift
import SwiftUI

struct BridgeViewV2: View {
    @Environment(WalletStore.self) private var store
    @State private var selectedTab: BridgeTab = .deposit
    @State private var amount: String = ""
    @State private var selectedToken: String = "ETH"
    @State private var l1Address: String = ""
    @State private var isProcessing: Bool = false
    @State private var statusMessage: String?

    enum BridgeTab: String, CaseIterable {
        case deposit = "Deposit"
        case withdraw = "Withdraw"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                Text("Bridge")
                    .font(V2Fonts.title(24))
                    .foregroundColor(V2Colors.textWhite)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Tab selector
                HStack(spacing: 0) {
                    ForEach(BridgeTab.allCases, id: \.self) { tab in
                        Button {
                            withAnimation { selectedTab = tab }
                        } label: {
                            Text(tab.rawValue)
                                .font(V2Fonts.bodySemibold(14))
                                .foregroundColor(selectedTab == tab ? V2Colors.textWhite : V2Colors.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(selectedTab == tab ? V2Colors.aztecDark : Color.clear)
                                .cornerRadius(8)
                        }
                    }
                }
                .background(V2Colors.cardBackground)
                .cornerRadius(10)

                // Token selector
                HStack {
                    Text("Token")
                        .font(V2Fonts.label(12))
                        .foregroundColor(V2Colors.textSecondary)
                    Spacer()
                    Menu {
                        Button("ETH") { selectedToken = "ETH" }
                        Button("USDC") { selectedToken = "USDC" }
                        Button("Fee Juice") { selectedToken = "FEE" }
                    } label: {
                        HStack {
                            Text(selectedToken)
                                .font(V2Fonts.bodySemibold(14))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(V2Colors.textWhite)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(V2Colors.cardBackground)
                        .cornerRadius(8)
                    }
                }

                // Amount input
                VStack(alignment: .leading, spacing: 6) {
                    Text("Amount")
                        .font(V2Fonts.label(12))
                        .foregroundColor(V2Colors.textSecondary)
                    TextField("0.0", text: $amount)
                        .font(V2Fonts.title(28))
                        .foregroundColor(V2Colors.textWhite)
                        .keyboardType(.decimalPad)
                }
                .padding()
                .background(V2Colors.cardBackground)
                .cornerRadius(12)

                // L1 address (for withdraw)
                if selectedTab == .withdraw {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("L1 Recipient Address")
                            .font(V2Fonts.label(12))
                            .foregroundColor(V2Colors.textSecondary)
                        TextField("0x...", text: $l1Address)
                            .font(V2Fonts.body(14))
                            .foregroundColor(V2Colors.textWhite)
                    }
                    .padding()
                    .background(V2Colors.cardBackground)
                    .cornerRadius(12)
                }

                // Action button
                Button {
                    Task { await executeBridge() }
                } label: {
                    HStack {
                        if isProcessing {
                            ProgressView().tint(.white)
                        }
                        Text(selectedTab == .deposit ? "Deposit to Aztec" : "Withdraw to L1")
                            .font(V2Fonts.bodySemibold(16))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(amount.isEmpty ? V2Colors.textSecondary.opacity(0.3) : V2Colors.aztecDark)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(amount.isEmpty || isProcessing)

                // Status
                if let msg = statusMessage {
                    Text(msg)
                        .font(V2Fonts.body(12))
                        .foregroundColor(V2Colors.textSecondary)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(V2Colors.cardBackground)
                        .cornerRadius(8)
                }

                // Transaction history
                if !store.bridgeTransactions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recent Bridge Transactions")
                            .font(V2Fonts.bodySemibold(14))
                            .foregroundColor(V2Colors.textWhite)

                        ForEach(store.bridgeTransactions.prefix(5)) { tx in
                            HStack {
                                Image(systemName: tx.type == .deposit ? "arrow.down.circle" : "arrow.up.circle")
                                    .foregroundColor(tx.type == .deposit ? .green : .orange)
                                VStack(alignment: .leading) {
                                    Text("\(tx.type.rawValue.capitalized) \(tx.amount) \(tx.token)")
                                        .font(V2Fonts.body(13))
                                        .foregroundColor(V2Colors.textWhite)
                                    Text(tx.status.rawValue)
                                        .font(V2Fonts.label(11))
                                        .foregroundColor(V2Colors.textSecondary)
                                }
                                Spacer()
                                Text(tx.timestamp.formatted(.dateTime.hour().minute()))
                                    .font(V2Fonts.label(10))
                                    .foregroundColor(V2Colors.textSecondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding()
                    .background(V2Colors.cardBackground)
                    .cornerRadius(12)
                }
            }
            .padding()
        }
        .background(V2Colors.background)
    }

    func executeBridge() async {
        isProcessing = true
        statusMessage = selectedTab == .deposit ? "Preparing deposit..." : "Preparing withdrawal..."

        let tx = WalletStore.BridgeTransaction(
            id: UUID(),
            type: selectedTab == .deposit ? .deposit : .withdraw,
            token: selectedToken,
            amount: amount,
            status: .pending,
            l1TxHash: nil,
            l2TxHash: nil,
            timestamp: Date()
        )
        store.bridgeTransactions.insert(tx, at: 0)
        store.saveBridgeTransactions()

        // Bridge execution will be wired to PXEBridge in Phase 4
        try? await Task.sleep(for: .seconds(2))
        statusMessage = "Bridge transaction submitted. Waiting for confirmation..."
        isProcessing = false
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add ios/CelariWallet/CelariWallet/V2/Views/BridgeViewV2.swift
git commit -m "feat(ios): add BridgeViewV2 for L1↔L2 token bridging

Deposit and withdraw UI with token selector, amount input, transaction
history. Bridge execution placeholder — will be wired in Phase 4."
```

---

## Task 3: Tab Navigation Expansion

**Files:**
- Modify: `ios/CelariWallet/CelariWallet/V2/RootViewV2.swift`
- Modify: `ios/CelariWallet/CelariWallet/V2/Components/TabBarV2.swift`

- [ ] **Step 1: Add bridge tab to V2Tab enum**

In RootViewV2.swift or TabBarV2.swift (wherever V2Tab enum is), change:
```swift
enum V2Tab: Int, CaseIterable {
    case home, send, bridge, receive, history
}
```

- [ ] **Step 2: Add bridge case to tab bar icons**

In TabBarV2.swift, add icon mapping for `.bridge`:
- Icon: `"arrow.left.arrow.right.circle.fill"` or similar
- Label: `"Bridge"`

- [ ] **Step 3: Add bridge case to RootViewV2 switch**

```swift
case .bridge: BridgeViewV2()
```

- [ ] **Step 4: Commit**

```bash
git add ios/CelariWallet/CelariWallet/V2/
git commit -m "feat(ios): add Bridge tab to V2 navigation

Expand tab bar from 4 to 5 tabs: Home, Send, Bridge, Receive, History."
```

---

## Task 4: Deep Linking for WalletConnect

**Files:**
- Modify: `ios/CelariWallet/CelariWallet/CelariWalletApp.swift`
- Modify: `ios/CelariWallet/project.yml`

- [ ] **Step 1: Add URL scheme to project.yml**

In project.yml, under the CelariWallet target settings, add URL types. Find the settings section and add:
```yaml
    INFOPLIST_KEY_CFBundleURLTypes: "$(inherited)"
```

Or add to the info plist section:
```yaml
    info:
      properties:
        CFBundleURLTypes:
          - CFBundleURLSchemes:
              - celari
            CFBundleURLName: com.celari.wallet
```

- [ ] **Step 2: Add onOpenURL handler to CelariWalletApp.swift**

In the WindowGroup body, add:
```swift
.onOpenURL { url in
    handleDeepLink(url)
}
```

Add the handler method:
```swift
func handleDeepLink(_ url: URL) {
    guard url.scheme == "celari" else { return }

    switch url.host {
    case "wc":
        // celari://wc?uri=wc:...
        if let uri = url.queryParameters?["uri"] ?? URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "uri" })?.value {
            Task {
                try? await pxeBridge.wcPair(uri: uri)
            }
        }
    default:
        break
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add ios/CelariWallet/CelariWallet/CelariWalletApp.swift ios/CelariWallet/project.yml
git commit -m "feat(ios): add deep linking for WalletConnect pairing

Handle celari://wc?uri=... URLs for automatic WC session pairing."
```

---

## Task 5: DEX Interaction Layer (Track 2)

**Files:**
- Create: `src/utils/dex.ts`

- [ ] **Step 1: Create DEX client**

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

export class DexClient {
  private nodeUrl: string;

  constructor(nodeUrl: string) {
    this.nodeUrl = nodeUrl;
  }

  async getQuote(
    tokenIn: string,
    tokenOut: string,
    amountIn: bigint,
    slippage: number = 0.01
  ): Promise<SwapQuote> {
    // Query on-chain AMM contract for swap quote
    // For now, return a placeholder — will be wired to actual DEX contracts
    const estimatedOut = amountIn * 99n / 100n; // 1% placeholder spread
    return {
      tokenIn,
      tokenOut,
      amountIn,
      amountOut: estimatedOut,
      priceImpact: 0.01,
      estimatedGas: 500000n,
      expiresAt: Date.now() + 30000,
    };
  }

  async executeSwap(quote: SwapQuote, walletAddress: string): Promise<string> {
    // Execute swap through DEX contract
    // Returns tx hash
    throw new Error("DEX swap not yet connected to contract");
  }

  async getSupportedPairs(): Promise<TokenPair[]> {
    // Query DEX for available trading pairs
    return [];
  }
}
```

- [ ] **Step 2: Add DEX handlers to offscreen.js**

In offscreen.js, add cases for DEX operations:

```javascript
case "PXE_DEX_GET_QUOTE": {
  const { tokenIn, tokenOut, amountIn, slippage } = data;
  // Forward to DEX client
  return { success: true, quote: { tokenIn, tokenOut, amountIn, amountOut: "0", priceImpact: 0 } };
}

case "PXE_DEX_EXECUTE_SWAP": {
  const { quote } = data;
  // Execute swap via contract interaction
  return { success: false, error: "DEX not yet connected" };
}
```

- [ ] **Step 3: Commit**

```bash
git add src/utils/dex.ts extension/public/src/offscreen.js
git commit -m "feat: add DEX interaction layer with quote and swap stubs

DexClient TypeScript class with getQuote/executeSwap/getSupportedPairs.
Offscreen.js handlers for PXE_DEX_GET_QUOTE and PXE_DEX_EXECUTE_SWAP.
Will be connected to actual DEX contracts when available."
```

---

## Task 6: iOS Build Verification

- [ ] **Step 1: xcodegen + build**
```bash
cd ios/CelariWallet && xcodegen generate
xcodebuild -scheme CelariWallet -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "(BUILD|error:)"
```

- [ ] **Step 2: Commit xcodeproj**
```bash
git add ios/CelariWallet/CelariWallet.xcodeproj/
git commit -m "build(ios): regenerate xcodeproj after Phase 3 changes"
```

---

## Summary

| Task | Track | What | Files |
|------|-------|------|-------|
| 1 | 1 | Bridge state management | WalletStore.swift |
| 2 | 1 | BridgeViewV2 UI | BridgeViewV2.swift (new) |
| 3 | 1 | Tab navigation | RootViewV2, TabBarV2 |
| 4 | 1 | Deep linking | CelariWalletApp, project.yml |
| 5 | 2 | DEX layer | dex.ts (new), offscreen.js |
| 6 | 1 | Build verification | xcodeproj |
