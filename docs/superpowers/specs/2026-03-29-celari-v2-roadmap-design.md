# Celari Wallet v2 — 3-Month iOS + Mainnet Roadmap

**Date:** 2026-03-29
**Timeline:** 12 weeks (April–June 2026)
**Strategy:** Dual-Track Parallel
**Team:** 2-3 developers
**Priority:** iOS-first, mainnet-ready, full feature suite

---

## Executive Summary

3 ayda Celari Wallet'ı iOS App Store'da yayınlanmış, Aztec mainnet'te çalışan, tam özellikli bir privacy wallet'a dönüştürmek. Dual-track paralel çalışmayla riskli işler (Swoirenberg native prover, bridge contracts) erken başlar, iOS UI ve kullanıcı deneyimi paralelde ilerler.

**Hedef feature set:** Core wallet + L1↔L2 Bridge + DEX Swap + Guardian Recovery + WalletConnect v2 + Push Notifications + iOS Widget

---

## Track Structure

```
Track 1 (iOS/UI Lead):                Track 2 (Contract/Infra Lead):
─────────────────────────             ──────────────────────────────
Hafta 1-2: Foundation                  Hafta 1-2: Swoirenberg
Hafta 3-4: Guardian Recovery UI        Hafta 3-4: Bridge Contracts
Hafta 5-6: Bridge UI + WC v2          Hafta 5-6: DEX Layer
Hafta 7-8: DEX UI + Push + Widget     Hafta 7-8: Mainnet Deploy + E2E
Hafta 9-10: TestFlight Beta           Hafta 9-10: Security + Prover
Hafta 11-12: App Store Submission     Hafta 11-12: Mainnet Launch
```

---

## Phase 1: Foundation (Hafta 1-2)

### 1.1 SDK Upgrade (v4.1.0-rc.2 → v4.1.2)

**Files:**
- `package.json` — All 14 `@aztec/*` packages → `4.1.2`
- `contracts/celari_passkey_account/Nargo.toml` — `tag` → `v4.1.2`
- `contracts/celari_recoverable_account/Nargo.toml` — `tag` → `v4.1.2`

**Breaking changes to handle:**
1. `.send()` / `.simulate()` return type now includes `offchainEffects` and `offchainMessages`
   - Affected files: `extension/public/src/offscreen.js` (all `.send()` and `.simulate()` calls)
   - Fix: Update destructuring patterns
2. Public event pagination: `getPublicEvents` now accepts `{ from, limit }` params
   - Low impact — wallet doesn't paginate public events currently
3. L2-to-L1 message witness: Now takes `(message, txHash)` instead of epoch
   - Affected: `bridge/sdk/bridge-client.ts` (withdraw flow)
   - Fix: Update API call signatures

**Additional deprecations:**
- `PublicFeePaymentMethod` and `PrivateFeePaymentMethod` deprecated
- Our `SponsoredFPC + FeeJuice` fallback pattern is the recommended approach — no change needed

**Steps:**
```bash
# 1. Update versions
# 2. Clean install
rm -rf node_modules && npm install --legacy-peer-deps
# 3. Recompile contracts
cd contracts/celari_passkey_account && aztec compile
cd contracts/celari_recoverable_account && aztec compile
# 4. Regenerate TypeScript artifacts
aztec codegen contracts/celari_passkey_account/target -o src/artifacts --nr
# 5. Rebuild offscreen.js (both extension and iOS)
node extension/build.mjs
# 6. Copy iOS resources
cp extension/dist/src/offscreen.js ios/CelariWallet/CelariWallet/Resources/
```

### 1.2 Security Fixes

**A3 — CORS Whitelist (`scripts/deploy-server.ts`)**
```typescript
// Before: Access-Control-Allow-Origin: *
// After:
const ALLOWED_ORIGINS = [
  /^chrome-extension:\/\//,
  /^http:\/\/localhost/,
  process.env.CORS_ORIGIN,
].filter(Boolean);
```

**A5 — PostMessage Origin (`extension/public/src/content.js`)**
```javascript
// Before: window.postMessage({...}, "*")
// After:  window.postMessage({...}, window.location.origin)
```

**A1 — Dead Code Cleanup**
- Remove `extension/src/` directory (unused, manifest uses `public/src/`)

**B6 — Version Sync**
- Align all version strings to `0.5.0`: manifest.json, package.json, inpage.js

### 1.3 PXE Performance Optimization (iOS)

**Lazy PXE Initialization:**
- `WalletStore.swift`: Add `pxeState` enum: `.notStarted` → `.initializing` → `.syncing` → `.ready`
- Show Dashboard immediately with cached balances
- PXE starts in background, UI updates reactively when `.ready`

**FileManager Persistence:**
- Move 56MB PXE state from UserDefaults to `FileManager`
- Path: `Documents/pxe-state.enc` (AES-256-GCM encrypted)
- Faster read/write, no UserDefaults size warnings

**Incremental Sync:**
- Store last synced block number in Keychain
- On restore, sync only from `lastBlock + 1` instead of full re-sync

### 1.4 Swoirenberg XCFramework Stabilization (Track 2)

**Root cause analysis of `chonk_prove` crash:**
- `fork/swoirenberg/` — Debug XCFramework build
- Test on real device (not simulator) — ARM64 specific issues
- Memory pressure analysis: Proving may OOM on older devices

**Implementation:**
- `NativeProver.swift`: Crash guard with `NSSetUncaughtExceptionHandler`
- Graceful fallback: If native prove throws → fall back to WASM
- `PXEBridge.swift`: `window.nativeProver.available` = true when stable

**Decision gate (end of week 4):**
- Native prover stable on iPhone 13+ → ship it
- Unstable → stay on WASM, add CHONK prover to backlog

---

## Phase 2: Guardian Recovery + Bridge Contracts (Hafta 3-4)

### 2.1 Recoverable Account Contract (v0.1.0 → v0.2.0)

**File:** `contracts/celari_recoverable_account/src/main.nr`

**Complete and test:**
- `setup_guardians(guardian_hash_0, guardian_hash_1, guardian_hash_2, threshold)` — Owner sets 3 guardians
- `initiate_recovery(new_key_x, new_key_y, guardian_sigs)` — 2-of-3 approval
- `cancel_recovery()` — Owner cancels within time-lock window
- `execute_recovery()` — Finalizes key rotation after 24h (7200 blocks)
- IPFS CID storage for encrypted recovery bundle

**Testing:**
- TXE tests: `aztec test` in contract directory
- E2E: Deploy → setup guardians → simulate recovery → cancel → re-initiate → execute

### 2.2 Guardian iOS UI

**New/Updated Views:**
- `GuardianSetupView.swift` — 3 guardian address input, threshold selector, confirm & deploy
- `RecoverAccountView.swift` — Recovery initiation, 24h countdown timer, cancel button
- `WalletStore.swift` additions:
  ```swift
  enum GuardianStatus { case notSetup, configured, recoveryPending(deadline: Date), recovered }
  var guardianStatus: GuardianStatus = .notSetup
  var guardians: [String] = [] // 3 guardian addresses
  ```

**Recovery E2E Flow:**
```
Setup:    Settings → Guardian Setup → Enter 3 addresses → Confirm → Deploy TX
Recovery: New device → Restore app → Enter guardian contacts → 2 guardians approve
          → 24h countdown → Key rotated → Account restored
Cancel:   Old device → Settings → Active Recovery alert → Cancel Recovery → TX
```

### 2.3 Bridge L1 Contract (Solidity)

**File:** `bridge/contracts/l1/TokenPortal.sol`

**Functions:**
- `depositToAztecPublic(address token, uint256 amount, bytes32 to, bytes32 secretHash)` → sends L1→L2 message
- `depositToAztecPrivate(address token, uint256 amount, bytes32 secretHashForRedeemingMintedNotes, bytes32 secretHashForL2MessageConsumption)` → private deposit
- `withdraw(address token, uint256 amount, address recipient, bool withCaller)` → L2→L1 withdrawal claim

**Deploy:** Ethereum Sepolia via `bridge/scripts/deploy-l1.ts` (Forge)

### 2.4 Bridge L2 Contract (Noir)

**File:** `bridge/contracts/l2/src/main.nr`

**Functions:**
- `claim_public(to, amount, secret)` → Mint bridged tokens publicly
- `claim_private(to, amount, secret)` → Mint bridged tokens privately
- `exit_to_l1_public(token, amount, recipient, nonce)` → Burn + L2→L1 message
- `exit_to_l1_private(token, amount, recipient, nonce)` → Private exit

**v4.1.2 update:** L2-to-L1 message witness now takes `(message, txHash)` — update `exit_to_l1_*` functions

### 2.5 Bridge SDK

**File:** `bridge/sdk/bridge-client.ts`

```typescript
export class BridgeClient {
  async deposit(token: AztecAddress, amount: bigint, toPrivate: boolean): Promise<TxHash>
  async withdraw(token: AztecAddress, amount: bigint, l1Recipient: string): Promise<TxHash>
  async getDepositStatus(txHash: string): Promise<BridgeStatus>
  async getWithdrawStatus(txHash: string): Promise<BridgeStatus>
}

type BridgeStatus = 'pending' | 'l1Confirmed' | 'l2Claimed' | 'failed'
```

---

## Phase 3: Bridge UI + WalletConnect v2 (Hafta 5-6)

### 3.1 Bridge iOS UI

**New View:** `BridgeView.swift`

**Deposit flow:**
1. Token selector (ETH, USDC, etc.)
2. Amount input + L1 balance display
3. Connect L1 wallet (WalletConnect → MetaMask/Rainbow)
4. ERC-20 approve TX (if token, not ETH)
5. Deposit TX → progress indicator
6. Wait for L2 claim → auto-claim or manual claim button
7. Success → balance updated

**Withdraw flow:**
1. Token selector + amount from L2 balance
2. L1 recipient address input (or connected wallet)
3. Burn TX on L2 → progress
4. Wait for L1 message availability
5. Claim on L1 → complete

**State:** `WalletStore.swift`
```swift
struct BridgeTransaction: Codable, Identifiable {
    let id: UUID
    let type: BridgeType // .deposit, .withdraw
    let token: String
    let amount: String
    let status: BridgeStatus
    let l1TxHash: String?
    let l2TxHash: String?
    let timestamp: Date
}
var bridgeTransactions: [BridgeTransaction] = []
```

### 3.2 WalletConnect v2

**Deep linking:**
- `project.yml`: Add URL scheme `celari://`
- `CelariWalletApp.swift`: Handle `celari://wc?uri=wc:...` URLs
- Universal link: `https://celariwallet.com/wc?uri=...`

**Session management:**
- `WalletConnectManager.swift` (new Core file)
- Session persistence in Keychain
- Auto-reconnect on app launch
- Heartbeat/keepalive for active sessions

**Supported methods:**
```swift
enum WCMethod: String {
    case sendTransaction = "aztec_sendTransaction"
    case signMessage = "aztec_signMessage"
    case getAccounts = "aztec_getAccounts"
    case getBalance = "aztec_getBalance"
}
```

**Approval UI:** `WcApproveView.swift`
- dApp name, icon, URL
- Requested method + params (human-readable)
- Gas estimate
- Approve (biometric) / Reject buttons

### 3.3 DEX Contract Interaction Layer (Track 2)

**File:** `src/utils/dex.ts`

```typescript
export interface SwapQuote {
  tokenIn: AztecAddress
  tokenOut: AztecAddress
  amountIn: bigint
  amountOut: bigint
  priceImpact: number // percentage
  route: SwapRoute[]
  estimatedGas: bigint
}

export class DexClient {
  async getQuote(tokenIn, tokenOut, amountIn, slippage): Promise<SwapQuote>
  async executeSwap(quote, wallet): Promise<TxHash>
  async getSupportedPairs(): Promise<TokenPair[]>
}
```

**DEX integration targets:** Shieldswap (primary), Nemi (secondary)
- ABI import from deployed contracts
- `offscreen.js`: Add `dex_getQuote` and `dex_executeSwap` PXE bridge methods

---

## Phase 4: DEX UI + Push + Widget (Hafta 7-8)

### 4.1 DEX Swap iOS UI

**New View:** `SwapView.swift`

**UI Elements:**
- Token pair selector (flip button for reverse)
- Amount input → real-time quote (debounced 500ms)
- Quote display: output amount, price impact, slippage, gas
- "Swap" button → ConfirmTxView → biometric → prove → send
- Transaction result: success/fail with TX hash

**Settings:** Slippage tolerance (0.5%, 1%, 2%, custom)

**Tab bar update:** Dashboard | Send | Swap | Bridge | Settings

### 4.2 Push Notifications

**New file:** `Core/NotificationManager.swift`

**Local notifications (no server):**
- TX confirmed: "Transfer of 100 TOKEN completed"
- TX failed: "Transfer failed — insufficient balance"
- Guardian recovery: "Recovery initiated — 24h to cancel"
- Bridge claim ready: "Your bridged tokens are ready to claim"
- WC session request: "dApp X wants to connect"

**Remote notifications (simple backend):**
- Incoming private transfer detected
- Guardian recovery initiated by third party
- New Aztec network upgrade available

**Setup:**
- `project.yml`: Push Notification entitlement
- `CelariWalletApp.swift`: `UNUserNotificationCenter.requestAuthorization`
- APNs certificate in App Store Connect

### 4.3 iOS Widget (WidgetKit)

**New target:** `CelariWidget/`

**Widget types:**
- **Small (2x2):** Total balance in USD equivalent
- **Medium (4x2):** Top 3 tokens with balances

**Data sharing:**
- App Group: `group.com.celari.wallet`
- `project.yml`: Add App Group entitlement to both app and widget targets
- Shared `UserDefaults(suiteName: "group.com.celari.wallet")` for balance data
- `WalletStore.swift`: Write balance snapshot to shared container on update

**Refresh:** `TimelineProvider` with 15-minute refresh interval

### 4.4 Mainnet Contract Deployment (Track 2)

**Contracts to deploy:**
- `celari_passkey_account` → `https://rpc.aztec.network/`
- `celari_recoverable_account` → `https://rpc.aztec.network/`

**Fee strategy:** FeeJuice only (SponsoredFPC not available on mainnet alpha)

**Deploy verification:**
- Contract address deterministic from artifact hash + salt
- Verify via Aztecscan
- Update network presets with deployed addresses

### 4.5 E2E Integration Tests

**Testnet full flow:**
1. Account: Create → Deploy → Verify
2. Transfer: Private → Public → Shield → Unshield
3. Guardian: Setup → Initiate recovery → Cancel → Re-initiate → Execute
4. WalletConnect: Pair → Approve TX → Verify result
5. DEX: Get quote → Execute swap → Verify balances
6. Bridge: Deposit L1→L2 → Claim → Withdraw L2→L1 → Claim

**iOS XCUITest:**
- Onboarding flow (passkey creation)
- Dashboard → Send → Receive
- Settings → Network switch
- Basic smoke test for TestFlight confidence

---

## Phase 5: TestFlight + Security + App Store (Hafta 9-12)

### 5.1 TestFlight Beta (Hafta 9-10)

**Setup:**
- App Store Connect: Team GBQUC68GE9, Bundle ID `com.celari.wallet`
- Certificates: Distribution certificate + provisioning profile
- TestFlight metadata: App description, beta notes, feedback link

**Beta testing:**
- Internal group: 10-20 testers
- Duration: 2+ weeks before App Store submission
- Focus areas: Onboarding UX, first transaction, bridge flow, crash rate

**Feedback loop:**
- TestFlight in-app feedback
- Crash reports via Xcode Organizer
- Weekly bug triage → fix → new build

### 5.2 Security Hardening (Hafta 9-10, Track 2)

**Network security:**
- SSL/TLS certificate pinning for Aztec RPC endpoints
- ATS configuration review in `Info.plist`

**App security:**
- Jailbreak detection (warning, not blocking)
- Sensitive data memory wipe after use
- Keychain access control: `.biometryCurrentSet` for passkeys

**Code security:**
- Input validation on all address/amount fields
- `offscreen.js` CSP review
- No secrets in binary (check with `strings` tool)

### 5.3 Native Prover Decision (Hafta 9-10)

**If stable (week 4 gate passed):**
- Enable `window.nativeProver.available = true`
- `PXEBridge.swift`: Route prove calls to `NativeProver`
- Benchmark: Log proving times (native vs WASM)
- Keep WASM as automatic fallback

**If unstable:**
- Clean disable: Remove Swoirenberg dependency from `project.yml`
- Keep `NativeProver.swift` but return `.unavailable`
- Add CHONK prover tracking issue for future

### 5.4 App Store Submission (Hafta 11-12)

**Required assets:**
- Privacy Policy URL (hosted on celariwallet.com)
- Terms of Service URL
- App Store screenshots: iPhone 15 Pro (6.7"), iPhone SE (4.7")
- App description (TR + EN localization)
- Keywords: privacy wallet, aztec, zero knowledge, passkey, crypto

**Apple Review preparation:**
- Demo account/instructions for reviewer
- Encryption compliance (uses AES-256-GCM, ECDSA P256)
- Crypto wallet category: Finance
- Age rating: 17+ (cryptocurrency)

**App Review notes:**
```
This app is a cryptocurrency wallet for the Aztec Network (privacy-focused L2).
Authentication uses WebAuthn/Passkeys (Face ID/Touch ID) — no seed phrases.
Test account: [provide testnet account with test tokens]
Testnet RPC: https://rpc.testnet.aztec-labs.com/
```

### 5.5 Mainnet Launch

**Pre-launch checklist:**
- [ ] All security fixes applied
- [ ] SDK v4.1.2 stable, contracts deployed
- [ ] TestFlight 2+ weeks crash-free
- [ ] Privacy Policy + ToS published
- [ ] App Store metadata complete
- [ ] Crash rate < 1%
- [ ] Cold start < 5s (lazy PXE)
- [ ] Native prover OR WASM fallback stable
- [ ] FeeJuice payment flow tested
- [ ] Guardian recovery e2e verified
- [ ] Bridge deposit/withdraw e2e verified
- [ ] Monitoring/alerting in place

**Rollback plan:**
- Remote config flag: `mainnet_enabled` (default: true)
- If critical bug: Set flag to false → app falls back to testnet
- Force update mechanism via App Store version check

---

## Risk Register

| Risk | Impact | Mitigation |
|------|--------|------------|
| Swoirenberg unstable | Medium | Week 4 decision gate → WASM fallback |
| Aztec mainnet delay | High | Ship on testnet first, mainnet as update |
| Apple rejects crypto wallet | High | Prepare detailed review notes, demo account |
| Bridge contract vulnerability | Critical | Security review before mainnet, testnet-only initially |
| SDK v5 breaks compatibility | Low | v5 is July 2026, after our launch |
| DEX contracts not ready | Medium | Ship without DEX, add in v2.1 update |
| SponsoredFPC unavailable on mainnet | Low | FeeJuice fallback already implemented |

---

## Success Metrics

- **TestFlight (week 10):** 20+ testers, <1% crash rate, >80% onboarding completion
- **App Store (week 12):** Approved and published
- **Mainnet (week 12):** Contracts deployed, first real transactions
- **Performance:** Cold start <5s, proof time <10s (native) or <30s (WASM)
- **Feature completeness:** All 6 features shipped (core, bridge, DEX, guardian, WC, notifications)
