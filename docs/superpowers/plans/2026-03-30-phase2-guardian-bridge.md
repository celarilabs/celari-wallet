# Phase 2: Guardian Recovery + Bridge — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete guardian recovery flow (IPFS + notification + state management) and finalize bridge L1 deployment. Most backend code (contract, PXEBridge, offscreen.js, bridge SDK) is already production-ready.

**Architecture:** Guardian recovery contract and JS/Swift bridge layers are complete. Work focuses on: (1) IPFS storage for encrypted recovery bundles, (2) guardian state management in WalletStore, (3) V2 view polish, (4) bridge deployment automation.

**Tech Stack:** Swift 5.9, SwiftUI, TypeScript, Solidity (Forge), Noir

---

## Task 1: WalletStore Guardian State Management

**Files:**
- Modify: `ios/CelariWallet/CelariWallet/Core/WalletStore.swift`

Add guardian-related state tracking to WalletStore.

- [ ] **Step 1: Add GuardianStatus enum**

After the `PXEState` enum, add:

```swift
    enum GuardianStatus: Codable, Equatable {
        case notSetup
        case configured(guardianCount: Int)
        case recoveryPending(initiatedAt: Date, deadline: Date)
        case recovered
    }
```

- [ ] **Step 2: Add guardian state properties**

In the state variables section (around line 185+), add:

```swift
    // Guardian Recovery
    var guardianStatus: GuardianStatus = .notSetup
    var guardians: [String] = [] // 3 guardian addresses/identifiers
    var recoveryCountdownRemaining: String?
```

- [ ] **Step 3: Add checkGuardianStatus() method**

Add a method that queries the contract to determine guardian state:

```swift
    func checkGuardianStatus() async {
        guard pxeInitialized, let pxeBridge else { return }
        do {
            let configured = try await pxeBridge.isGuardianConfigured()
            if let isConfigured = configured["configured"] as? Bool, isConfigured {
                let recoveryActive = try await pxeBridge.checkRecoveryStatus()
                if let active = recoveryActive["active"] as? Bool, active,
                   let blockStart = recoveryActive["startBlock"] as? Int {
                    let deadline = Date().addingTimeInterval(Double(7200 - (blockStart % 7200)) * 12)
                    self.guardianStatus = .recoveryPending(initiatedAt: Date(), deadline: deadline)
                } else {
                    self.guardianStatus = .configured(guardianCount: 3)
                }
            } else {
                self.guardianStatus = .notSetup
            }
        } catch {
            walletLog.error("[WalletStore] Guardian status check failed: \(error.localizedDescription, privacy: .public)")
        }
    }
```

- [ ] **Step 4: Call checkGuardianStatus on PXE ready**

In `initialize()`, after `self.pxeState = .ready` (added in Phase 1), add:

```swift
                    await self.checkGuardianStatus()
```

- [ ] **Step 5: Add guardian persistence to loadFromStorage/saveToStorage**

In `loadFromStorage()`, add:
```swift
        if let data = UserDefaults.standard.data(forKey: "guardianStatus"),
           let status = try? JSONDecoder().decode(GuardianStatus.self, from: data) {
            self.guardianStatus = status
        }
        self.guardians = UserDefaults.standard.stringArray(forKey: "guardians") ?? []
```

In the save section, add:
```swift
        if let data = try? JSONEncoder().encode(guardianStatus) {
            UserDefaults.standard.set(data, forKey: "guardianStatus")
        }
        UserDefaults.standard.set(guardians, forKey: "guardians")
```

- [ ] **Step 6: Commit**

```bash
git add ios/CelariWallet/CelariWallet/Core/WalletStore.swift
git commit -m "feat(ios): add guardian status state management to WalletStore

Add GuardianStatus enum, checkGuardianStatus() query, and persistence
for guardian recovery state."
```

---

## Task 2: PXEBridge — Add Missing Recovery Methods

**Files:**
- Modify: `ios/CelariWallet/CelariWallet/Core/PXEBridge.swift`

The existing PXEBridge has 6 guardian methods but may be missing `checkRecoveryStatus`. Check and add if needed.

- [ ] **Step 1: Read PXEBridge.swift and verify existing methods**

Check lines 398-441 for these methods:
- `setupGuardians()`
- `initiateRecovery()`
- `executeRecovery()`
- `cancelRecovery()`
- `isGuardianConfigured()`
- `getRecoveryCid()`

- [ ] **Step 2: Add checkRecoveryStatus() if missing**

If not present, add after the existing guardian methods:

```swift
    func checkRecoveryStatus() async throws -> [String: Any] {
        return try await sendMessage("PXE_IS_RECOVERY_ACTIVE", params: [:])
    }
```

- [ ] **Step 3: Verify offscreen.js has matching handler**

Check that `PXE_IS_RECOVERY_ACTIVE` (or equivalent like `is_recovery_active`) is handled in offscreen.js. If the view function `is_recovery_active()` exists in the contract (it does per exploration), ensure the handler calls it.

- [ ] **Step 4: Commit**

```bash
git add ios/CelariWallet/CelariWallet/Core/PXEBridge.swift
git commit -m "feat(ios): add checkRecoveryStatus() to PXEBridge

Query on-chain recovery state for active recovery detection."
```

---

## Task 3: IPFS Recovery Bundle Storage

**Files:**
- Modify: `ios/CelariWallet/CelariWallet/V2/Views/GuardianSetupViewV2.swift`
- Create: `ios/CelariWallet/CelariWallet/Core/IPFSManager.swift`

Replace placeholder CID with real IPFS upload via Pinata or web3.storage.

- [ ] **Step 1: Create IPFSManager.swift**

```swift
import Foundation

/// Uploads encrypted recovery bundles to IPFS via Pinata.
/// Uses Pinata's public pinning API (no API key needed for small files).
actor IPFSManager {
    static let shared = IPFSManager()

    private let pinataGateway = "https://api.pinata.cloud/pinning/pinJSONToIPFS"

    /// Upload JSON data to IPFS and return the CID.
    func upload(json: [String: Any], apiKey: String) async throws -> String {
        let payload: [String: Any] = [
            "pinataContent": json,
            "pinataMetadata": ["name": "celari-recovery-\(UUID().uuidString.prefix(8))"]
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)

        var request = URLRequest(url: URL(string: pinataGateway)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw IPFSError.uploadFailed
        }

        let result = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let cid = result?["IpfsHash"] as? String else {
            throw IPFSError.noCID
        }
        return cid
    }

    /// Fetch recovery bundle from IPFS by CID.
    func fetch(cid: String) async throws -> [String: Any] {
        let url = URL(string: "https://gateway.pinata.cloud/ipfs/\(cid)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw IPFSError.invalidData
        }
        return json
    }

    enum IPFSError: Error, LocalizedError {
        case uploadFailed
        case noCID
        case invalidData

        var errorDescription: String? {
            switch self {
            case .uploadFailed: return "Failed to upload to IPFS"
            case .noCID: return "No CID returned from IPFS"
            case .invalidData: return "Invalid data from IPFS"
            }
        }
    }
}
```

- [ ] **Step 2: Update GuardianSetupViewV2 to use real IPFS upload**

In `GuardianSetupViewV2.swift`, find the section where the CID is generated (around lines 264-275). Replace the deterministic hash-based CID with actual IPFS upload:

Find the line that creates a fake/deterministic CID and replace with:
```swift
// Upload encrypted recovery bundle to IPFS
let recoveryPayload: [String: Any] = [
    "accountAddress": store.activeAccount?.address ?? "",
    "guardianEmails": guardianEmails,
    "threshold": 2,
    "encryptedKeys": encryptedBundle,
    "version": 1
]
let cid = try await IPFSManager.shared.upload(
    json: recoveryPayload,
    apiKey: store.pinataApiKey ?? ""
)
```

Note: If Pinata API key is not available, fall back to the existing deterministic CID approach. The IPFS upload should be best-effort, not blocking.

- [ ] **Step 3: Add pinataApiKey to WalletStore settings**

In `WalletStore.swift`, add:
```swift
    var pinataApiKey: String? {
        get { UserDefaults.standard.string(forKey: "pinataApiKey") }
        set { UserDefaults.standard.set(newValue, forKey: "pinataApiKey") }
    }
```

- [ ] **Step 4: Run xcodegen and verify build**

```bash
cd ios/CelariWallet && xcodegen generate
xcodebuild -scheme CelariWallet -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "(BUILD|error:)"
```

Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add ios/CelariWallet/CelariWallet/Core/IPFSManager.swift ios/CelariWallet/CelariWallet/V2/Views/GuardianSetupViewV2.swift ios/CelariWallet/CelariWallet/Core/WalletStore.swift
git commit -m "feat(ios): add IPFS recovery bundle storage via Pinata

Upload encrypted guardian recovery bundles to IPFS. Falls back to
deterministic CID if Pinata API key not configured."
```

---

## Task 4: Guardian Recovery V2 — Countdown Timer On-Chain Verification

**Files:**
- Modify: `ios/CelariWallet/CelariWallet/V2/Views/RecoverAccountViewV2.swift`

The V2 view has a local countdown timer but doesn't verify against on-chain block time.

- [ ] **Step 1: Add block-time based countdown**

Find the countdown timer section (around lines 218-236). Update to query actual block state:

```swift
    func updateCountdown() async {
        guard let pxeBridge = store.pxeBridge else { return }
        do {
            let status = try await pxeBridge.checkRecoveryStatus()
            if let startBlock = status["startBlock"] as? Int,
               let currentBlock = status["currentBlock"] as? Int {
                let blocksRemaining = max(0, 7200 - (currentBlock - startBlock))
                let secondsRemaining = blocksRemaining * 12 // ~12s per block
                let hours = secondsRemaining / 3600
                let minutes = (secondsRemaining % 3600) / 60
                let secs = secondsRemaining % 60
                countdownText = String(format: "%02d:%02d:%02d", hours, minutes, secs)

                if blocksRemaining == 0 {
                    canExecute = true
                }
            }
        } catch {
            // Fall back to local timer if query fails
        }
    }
```

- [ ] **Step 2: Commit**

```bash
git add ios/CelariWallet/CelariWallet/V2/Views/RecoverAccountViewV2.swift
git commit -m "feat(ios): verify recovery countdown against on-chain block time

Query actual block number to calculate remaining time-lock period
instead of relying solely on local timer."
```

---

## Task 5: Guardian Local Notification on Recovery

**Files:**
- Modify: `ios/CelariWallet/CelariWallet/Core/WalletStore.swift`

When guardian status changes to `.recoveryPending`, fire a local notification.

- [ ] **Step 1: Add notification import and helper**

At the top of WalletStore.swift, ensure `import UserNotifications` is present.

Add a helper method:

```swift
    func scheduleRecoveryNotification(deadline: Date) {
        let content = UNMutableNotificationContent()
        content.title = "Recovery Alert"
        content.body = "A guardian recovery was initiated. You have until \(deadline.formatted(.dateTime.hour().minute())) to cancel if this wasn't you."
        content.sound = .default
        content.categoryIdentifier = "RECOVERY_ALERT"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "recovery-alert", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)

        // Also schedule a reminder 1 hour before deadline
        let reminderInterval = max(1, deadline.timeIntervalSinceNow - 3600)
        let reminderContent = UNMutableNotificationContent()
        reminderContent.title = "Recovery Deadline Approaching"
        reminderContent.body = "1 hour left to cancel the guardian recovery if unauthorized."
        reminderContent.sound = .defaultCritical

        let reminderTrigger = UNTimeIntervalNotificationTrigger(timeInterval: reminderInterval, repeats: false)
        let reminderRequest = UNNotificationRequest(identifier: "recovery-reminder", content: reminderContent, trigger: reminderTrigger)
        UNUserNotificationCenter.current().add(reminderRequest)
    }
```

- [ ] **Step 2: Fire notification in checkGuardianStatus()**

In `checkGuardianStatus()`, when setting `.recoveryPending`, add:

```swift
                    self.guardianStatus = .recoveryPending(initiatedAt: Date(), deadline: deadline)
                    scheduleRecoveryNotification(deadline: deadline)
```

- [ ] **Step 3: Commit**

```bash
git add ios/CelariWallet/CelariWallet/Core/WalletStore.swift
git commit -m "feat(ios): local notification on guardian recovery initiation

Alert user immediately when recovery is detected. Schedule reminder
1 hour before time-lock deadline expires."
```

---

## Task 6: Bridge L1 Contract Review + Deploy Script

**Files:**
- Review: `bridge/contracts/l1/src/CelariBridgePortal.sol`
- Modify: `bridge/scripts/deploy-l1.ts`

- [ ] **Step 1: Read and verify L1 contract**

Read `bridge/contracts/l1/src/CelariBridgePortal.sol` and verify it has:
- `depositToAztecPublic()`
- `depositToAztecPrivate()`
- `withdraw()`
- Proper L1-L2 message passing via Inbox/Outbox

- [ ] **Step 2: Update deploy-l1.ts for testnet deployment**

Update `bridge/scripts/deploy-l1.ts` to support automated deployment (not just instructions). The script should:
- Read environment variables for RPC URL and private key
- Deploy via ethers.js or viem
- Save deployment to `.l1-deployment.json`

- [ ] **Step 3: Commit**

```bash
git add bridge/scripts/deploy-l1.ts
git commit -m "feat(bridge): automate L1 bridge contract deployment

Replace manual deployment instructions with automated script using
environment variables for Sepolia RPC and private key."
```

---

## Task 7: Bridge L2 Deploy Script Update for v4.1.2

**Files:**
- Modify: `bridge/scripts/deploy-l2.ts`
- Modify: `bridge/contracts/l2/celari_token_bridge/Nargo.toml` (if exists)

- [ ] **Step 1: Update L2 bridge contract Nargo.toml to v4.1.2**

If the bridge contracts have their own Nargo.toml with aztec dependency, update the tag to `v4.1.2`.

- [ ] **Step 2: Update deploy-l2.ts for v4.1.2 API**

Check if deploy-l2.ts uses any deprecated APIs. The L2-to-L1 message witness API changed in v4.1.2 — now takes `(message, txHash)` instead of epoch.

Update bridge-client.ts if it uses the old L2-to-L1 message witness API.

- [ ] **Step 3: Commit**

```bash
git add bridge/
git commit -m "feat(bridge): update L2 bridge for Aztec SDK v4.1.2

Update Nargo.toml tags and L2-to-L1 message witness API calls."
```

---

## Task 8: iOS Build Verification + xcodegen

**Files:**
- Regenerated: `ios/CelariWallet/CelariWallet.xcodeproj/`

- [ ] **Step 1: Regenerate Xcode project**

```bash
cd ios/CelariWallet && xcodegen generate
```

- [ ] **Step 2: Build and verify**

```bash
xcodebuild -scheme CelariWallet -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "(BUILD|error:)"
```

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add ios/CelariWallet/CelariWallet.xcodeproj/
git commit -m "build(ios): regenerate xcodeproj after Phase 2 changes"
```

---

## Summary

| Task | Track | What | Status Dependency |
|------|-------|------|-------------------|
| 1 | 1 | WalletStore guardian state | Independent |
| 2 | 1 | PXEBridge recovery methods | Independent |
| 3 | 1 | IPFS recovery bundle | Depends on 1 |
| 4 | 1 | Countdown timer on-chain | Depends on 2 |
| 5 | 1 | Recovery notification | Depends on 1 |
| 6 | 2 | Bridge L1 deploy script | Independent |
| 7 | 2 | Bridge L2 v4.1.2 update | Independent |
| 8 | 1 | iOS build verification | Depends on 1-5 |

**Estimated time:** Tasks 1-5 (Track 1): ~4-6 hours. Tasks 6-7 (Track 2): ~3-4 hours. Task 8: ~15 minutes.
