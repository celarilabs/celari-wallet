# v4.1.2 Stabilization Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the rollback from v4.2.0-aztecnr-rc.2 to v4.1.2 across all components so the project builds, deploys, and runs correctly.

**Architecture:** The project attempted a v4.2.0 upgrade (commits 3d84b2f, 7db26d5, bf52ef8, 93de9c5) but hit runtime failures (BigInt crash, FeeJuice issues). package.json was rolled back to v4.1.2 (uncommitted) but Nargo.toml files, deploy scripts, and offscreen.js still have v4.2.0 remnants. This plan completes the rollback in dependency order: contracts -> scripts -> offscreen.js -> build -> verify.

**Tech Stack:** TypeScript (tsx), Noir (Nargo.toml), esbuild, Node.js v22

**Current State:**
- `package.json` + `node_modules`: v4.1.2 (uncommitted change)
- `Nargo.toml` (4 files): v4.2.0-aztecnr-rc.2 (committed)
- Deploy scripts (3 files): use `NO_FROM` which doesn't exist in v4.1.2 (committed)
- `offscreen.js`: partially patched (uncommitted)
- Contract artifacts: compiled with v4.2.0 noir toolchain (noir_version: 1.0.0-beta.18)

**Key v4.1.2 API facts (verified):**
- `NO_FROM` does NOT exist in `@aztec/aztec.js/account`
- `AztecAddress.ZERO` exists and works as substitute
- `SponsoredFeePaymentMethod` is at `@aztec/aztec.js/fee/testing` (also at `@aztec/aztec.js/fee`)
- `getContractInstanceFromInstantiationParams` is at `@aztec/stdlib/contract`
- All other imports (AuthWitness, deriveKeys, loadContractArtifact, Contract, AccountManager) verified working

---

## Task 1: Fix Deploy Scripts — Remove NO_FROM

**Files:**
- Modify: `scripts/deploy_passkey_account.ts:27,130`
- Modify: `scripts/deploy-server.ts:29,96,258`
- Modify: `scripts/deploy-token.ts:14,45`

- [ ] **Step 1: Fix deploy_passkey_account.ts**

Remove the NO_FROM import (line 27) and replace its usage (line 130) with `AztecAddress.ZERO`:

```typescript
// Line 27: DELETE this line:
// import { NO_FROM } from "@aztec/aztec.js/account";

// Line 130: Change from:
//   from: NO_FROM,
// To:
    from: AztecAddress.ZERO,
```

`AztecAddress` is already imported on line 26.

- [ ] **Step 2: Fix deploy-server.ts**

Remove the NO_FROM import (line 29) and replace all usages (lines 96, 258):

```typescript
// Line 29: DELETE this line:
// import { NO_FROM } from "@aztec/aztec.js/account";

// Line 96: Change from NO_FROM to AztecAddress.ZERO
    from: AztecAddress.ZERO,

// Line 258: Change from NO_FROM to AztecAddress.ZERO
    from: AztecAddress.ZERO,
```

`AztecAddress` is already imported on line 28.

- [ ] **Step 3: Fix deploy-token.ts**

Remove the NO_FROM import (line 14) and replace usage (line 45):

```typescript
// Line 14: DELETE this line:
// import { NO_FROM } from "@aztec/aztec.js/account";

// Line 45: Change from NO_FROM to AztecAddress.ZERO
    from: AztecAddress.ZERO,
```

`AztecAddress` is already imported on line 13.

- [ ] **Step 4: Verify imports resolve**

Run:
```bash
node -e "import('@aztec/aztec.js/addresses').then(m => console.log('AztecAddress.ZERO:', m.AztecAddress.ZERO.toString()))"
```

Expected: `AztecAddress.ZERO: 0x0000...`

- [ ] **Step 5: Commit**

```bash
git add scripts/deploy_passkey_account.ts scripts/deploy-server.ts scripts/deploy-token.ts
git commit -m "fix: remove NO_FROM import from deploy scripts (v4.1.2 compat)

NO_FROM was added in v4.2.0 and doesn't exist in v4.1.2.
Replace with AztecAddress.ZERO which has the same effect."
```

---

## Task 2: Rollback Nargo.toml Files to v4.1.2

**Files:**
- Modify: `contracts/celari_passkey_account/Nargo.toml:8`
- Modify: `contracts/celari_recoverable_account/Nargo.toml:8`
- Modify: `bridge/contracts/l2/bridged_token/Nargo.toml:8`
- Modify: `bridge/contracts/l2/celari_token_bridge/Nargo.toml:8`

- [ ] **Step 1: Update celari_passkey_account/Nargo.toml**

Line 8, change:
```toml
# FROM:
aztec = { git = "https://github.com/AztecProtocol/aztec-packages", tag = "v4.2.0-aztecnr-rc.2", directory = "noir-projects/aztec-nr/aztec" }
# TO:
aztec = { git = "https://github.com/AztecProtocol/aztec-packages", tag = "v4.1.2", directory = "noir-projects/aztec-nr/aztec" }
```

- [ ] **Step 2: Update celari_recoverable_account/Nargo.toml**

Same change on line 8.

- [ ] **Step 3: Update bridged_token/Nargo.toml**

Same change on line 8.

- [ ] **Step 4: Update celari_token_bridge/Nargo.toml**

Same change on line 8.

- [ ] **Step 5: Commit**

```bash
git add contracts/celari_passkey_account/Nargo.toml \
       contracts/celari_recoverable_account/Nargo.toml \
       bridge/contracts/l2/bridged_token/Nargo.toml \
       bridge/contracts/l2/celari_token_bridge/Nargo.toml
git commit -m "chore: rollback Nargo.toml from v4.2.0-rc.2 to v4.1.2

Match contract dependencies with npm package versions."
```

---

## Task 3: Clean Up offscreen.js v4.1.2 Compatibility

**Files:**
- Modify: `extension/public/src/offscreen.js:18-21,1113-1119,1233-1236`

The offscreen.js has been partially patched. Clean up the remaining issues:

- [ ] **Step 1: Verify NO_FROM polyfill is correct**

Lines 18-21 should already have:
```javascript
// AztecAddress already imported from @aztec/aztec.js/addresses above
import { SponsoredFeePaymentMethod } from "@aztec/aztec.js/fee/testing";
// NO_FROM was added in v4.2.0; in v4.1.x we just use undefined
const NO_FROM = undefined;
```

This is correct for v4.1.2. No change needed.

- [ ] **Step 2: Verify deployAccountClientSide send() call**

Line 1118 currently uses `from: AztecAddress.ZERO`. This works in v4.1.2 (verified). No change needed.

- [ ] **Step 3: Verify faucet deploy send() call**

Line 1233-1236 should have `from:` removed (commented out for v4.1.2 compat). Verify this is the case.

- [ ] **Step 4: Remove debug console.log lines**

Lines 1115-1116 have debug logging added during the rollback. Remove them:
```javascript
// DELETE these debug lines:
// console.log(`[PXE] Deploy Step 4: paymentMethod.paymentContract = ...`);
// console.log(`[PXE] Deploy Step 4: deployMethod.address = ...`);
```

- [ ] **Step 5: Build offscreen.js**

Run:
```bash
node extension/build.mjs
```

Expected: Build succeeds, `extension/dist/src/offscreen.js` generated.

- [ ] **Step 6: Commit**

```bash
git add extension/public/src/offscreen.js
git commit -m "fix: clean up offscreen.js v4.1.2 compatibility patches

Remove debug logging, keep NO_FROM polyfill and AztecAddress.ZERO usage."
```

---

## Task 4: Fix package.json and Commit Pending Changes

**Files:**
- Modify: `package.json:64`
- Commit: `package.json` (already has v4.1.2 deps, uncommitted)
- Commit: `package-lock.json` (uncommitted)

- [ ] **Step 1: Fix Node.js engine requirement**

Line 64 currently says `"node": ">=24.12.0"` but the system runs Node v22.22.1. The v4.2.0 SDK needed Node 24; v4.1.2 works fine with Node 22. Change to:

```json
"engines": {
    "node": ">=22.0.0"
}
```

- [ ] **Step 2: Commit package.json + package-lock.json**

```bash
git add package.json package-lock.json
git commit -m "chore: rollback to Aztec SDK v4.1.2, fix Node engine requirement

Reverts v4.2.0-rc.2 upgrade that caused BigInt crash and FeeJuice failures.
Node >=22.0.0 is sufficient for v4.1.2."
```

---

## Task 5: Full Build Verification

**Files:** None (verification only)

- [ ] **Step 1: Build extension**

```bash
node extension/build.mjs
```

Expected: All 3 passes succeed, WASM files copied.

- [ ] **Step 2: Verify deploy script imports**

```bash
npx tsx --eval "import './scripts/deploy_passkey_account.ts'" 2>&1 | head -5
npx tsx --eval "import './scripts/deploy-server.ts'" 2>&1 | head -5
npx tsx --eval "import './scripts/deploy-token.ts'" 2>&1 | head -5
```

Expected: No "NO_FROM" import errors. (May fail on missing env vars — that's OK, we're checking imports.)

- [ ] **Step 3: Verify contract artifact compatibility**

```bash
node -e "
const fs = require('fs');
const art = JSON.parse(fs.readFileSync('contracts/celari_passkey_account/target/celari_passkey_account-CelariPasskeyAccount.json', 'utf8'));
console.log('Artifact name:', art.name);
console.log('Functions:', art.functions.map(f => f.name).join(', '));
console.log('Noir version:', art.noir_version);
console.log('Function count:', art.functions.length);
"
```

Expected: Artifact loads without errors. Note: Artifact was compiled with noir 1.0.0-beta.18 (v4.2.0 toolchain). If function selectors mismatch at runtime, contracts will need recompilation with `aztec compile` using v4.1.2 nargo.

- [ ] **Step 4: Quick smoke test — can PXE create a node client?**

```bash
node -e "
const { createAztecNodeClient } = require('@aztec/aztec.js/node');
const client = createAztecNodeClient('https://rpc.testnet.aztec-labs.com/');
client.getNodeInfo().then(info => {
  console.log('Node version:', info.nodeVersion);
  console.log('Chain ID:', info.l1ChainId);
  console.log('Protocol version:', info.protocolVersion);
}).catch(e => console.log('Connection error (expected if offline):', e.message?.substring(0, 100)));
"
```

Expected: Either shows node info (if testnet is reachable) or a clean connection error.

---

## Task 6: Commit CLAUDE.md Update

**Files:**
- Commit: `CLAUDE.md` (already modified, uncommitted)

- [ ] **Step 1: Review CLAUDE.md changes**

The CLAUDE.md has uncommitted changes (62 lines added). Review that it accurately reflects v4.1.2 status.

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md with v4.1.2 API notes and roadmap"
```

---

## Summary

| Task | Description | Risk | Time |
|------|-------------|------|------|
| 1 | Fix NO_FROM in deploy scripts | Low — mechanical replacement | 5 min |
| 2 | Rollback Nargo.toml to v4.1.2 | Low — reverting to known good state | 5 min |
| 3 | Clean offscreen.js patches | Low — removing debug code | 5 min |
| 4 | Fix package.json engine + commit | Low — already working | 3 min |
| 5 | Full build verification | None — read only | 5 min |
| 6 | Commit CLAUDE.md | Low — docs only | 2 min |

**Post-stabilization concerns (not in this plan):**
- Contract artifacts may need recompilation if function selectors mismatch (requires Docker + aztec-nargo v4.1.2)
- Bridge L2 contracts and SDK are stubs — need implementation
- WalletConnect integration not started
- iOS Widget disabled (Info.plist issue)
- Guardian recovery TODOs (IPFS, relay, timer)
