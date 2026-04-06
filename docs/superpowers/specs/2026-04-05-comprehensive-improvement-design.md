# Celari Wallet — Comprehensive Improvement Plan

**Date:** 2026-04-05
**Approach:** Balanced/Parallel (Wave Structure)
**Scope:** Security hardening, architecture refactoring, missing features, test coverage, performance optimization
**Timeline:** 3 waves, each ~1-2 weeks

---

## Executive Summary

Code review sonucu tespit edilen 5 iyileştirme alanını 3 dalga halinde, paralel track'ler kullanarak ele alıyoruz. Quick win güvenlik fix'leri ve eksik özellik altyapısı aynı anda başlar (Dalga 1), büyük refactoring ve test coverage paralel ilerler (Dalga 2), performans optimizasyonu ve son dokunuşlar en sonda gelir (Dalga 3).

---

## Wave 1 — Quick Wins (Güvenlik Fix'leri + Eksik Özellik Altyapısı)

İki paralel track. Her iş birbirinden bağımsız, sıralama önemli değil.

### Track A — Security Fixes

#### S1: Event Listener Memory Leak Fix

**File:** `extension/public/src/inpage.js:105-111`

**Problem:** `window.celari.on()` her çağrıda yeni bir `window.addEventListener("message", ...)` ekliyor. Unsubscribe mekanizması yok. Bir dApp her event için `on()` çağırdığında listener birikir.

**Fix:** Listener registry pattern ile unsubscribe fonksiyonu döndür.

```javascript
// Before (line 105-111):
on(event, callback) {
  window.addEventListener("message", (e) => {
    if (e.data?.target === "celari-inpage" && e.data?.event === event) {
      callback(e.data.payload);
    }
  });
},

// After:
on(event, callback) {
  const handler = (e) => {
    if (e.data?.target === "celari-inpage" && e.data?.event === event) {
      callback(e.data.payload);
    }
  };
  window.addEventListener("message", handler);
  return () => window.removeEventListener("message", handler);
},
```

**Test:** `src/test/unit/extension.test.ts` — add test for `on()` returning unsubscribe function.

#### S2: Empty Catch Blocks

**File:** `website/src/hooks/useCelariExtension.ts:18,35`

**Problem:** `.catch(() => {})` ve `catch {}` — hatalar yutulmuş. Extension yüklü değilse veya bağlantı kopmuşsa kullanıcı hiçbir hata görmez.

**Fix:**

```typescript
// Line 18: .catch(() => {})
// →
.catch((err) => {
  console.debug("[Celari] getAddress failed:", err.message);
});

// Line 35: catch {}
// →
catch (err) {
  console.debug("[Celari] connect failed:", (err as Error).message);
}
```

#### S3: Production Sourcemap Removal

**File:** `extension/build.mjs:67`

**Problem:** Production build'de offscreen.js.map 78 MB. Gereksiz dosya boyutu.

**Current state:** `sourcemap: isDev` zaten doğru yapılandırılmış (line 67). Ancak `--dev` flag'i olmadan build yapıldığında bile eski `.map` dosyaları temizlenmiyor.

**Fix:** Build script'e clean step ekle — build başında `dist/src/offscreen.js.map` varsa sil.

```javascript
// build.mjs başına ekle (pass 2'den önce):
import { unlinkSync } from "fs";
const oldMap = resolve(outdir, "src/offscreen.js.map");
if (existsSync(oldMap)) unlinkSync(oldMap);
```

#### S4: Version String Sync

**Files:** `extension/public/manifest.json`, `package.json`, `extension/public/src/inpage.js:59`

**Problem:** Tüm version string'lerin `0.5.0` olup olmadığını doğrula. İnpage.js line 59'da `version: "0.5.0"` var, diğerlerini kontrol et.

**Fix:** Tutarsızlık varsa hepsini `0.5.0` olarak sync et.

#### S5: Dead Code Cleanup

**Problem:** `extension/src/` dizini kullanılmıyor — manifest `public/src/` kullanıyor. Karışıklık yaratıyor.

**Fix:** `extension/src/` dizinini sil (varsa).

---

### Track B — Missing Feature Infrastructure

#### F1: DEX Client — Stub'ları Gerçek Interface'e Bağla

**File:** `src/utils/dex.ts`

**Current state:** 3 TODO — `getQuote()` placeholder döndürüyor, `executeSwap()` throw ediyor, `getSupportedPairs()` boş array döndürüyor.

**Design:** Aztec'te henüz stabil bir DEX (Shieldswap/Nemi) mainnet'te çalışmıyor. Bu yüzden:

1. `DexClient` class'ını contract ABI'ye bağlanmaya hazır hale getir
2. `getQuote()` — Eğer contract adresi tanımlıysa on-chain sorgu yap, yoksa `NotAvailable` hatası fırlat
3. `executeSwap()` — Contract interaction skeleton'ı yaz (parametre validation + contract call yapısı), ama asıl işlem DEX contract deploy edilince aktif olur
4. `getSupportedPairs()` — Hardcoded bir `SUPPORTED_PAIRS` config objesi oluştur, sonra on-chain'e geçilebilir
5. Constructor'a `dexContractAddress?: AztecAddress` parametresi ekle

**Not:** DEX contract'ı henüz deploy edilmediği için bu "hazır ama inactive" bir implementasyon olacak. Asıl DEX çalışması Phase 3-4'te (roadmap hafta 5-8).

#### F2: Recovery 24h Timer UI

**File:** `ios/CelariWallet/CelariWallet/V2/Views/RecoverAccountViewV2.swift`

**Current state:** TODO comment — 24h geri sayım UI'ı yok.

**Design:**
1. Recovery başlatıldığında `recoveryDeadline: Date` hesapla (on-chain block time × cooldown blocks)
2. SwiftUI `TimelineView` ile canlı geri sayım göster (saat:dakika:saniye)
3. Deadline dolduğunda "Execute Recovery" butonu aktif olsun
4. Background'da local notification schedule et (WalletStore.scheduleRecoveryNotification zaten mevcut, line 705)

#### F3: IPFS Guardian Relay — Mock'tan Gerçeğe

**File:** `ios/CelariWallet/CelariWallet/Views/Recovery/GuardianSetupView.swift`

**Current state:** TODO comments — "use actual IPFS service" ve "wire up when deployed"

**Design:** 
1. `IPFSManager.swift` zaten mevcut (`ios/CelariWallet/CelariWallet/Core/IPFSManager.swift`) — commit `c0b6720` ile Pinata entegrasyonu eklenmiş
2. Guardian setup flow'da recovery bundle'ı (encrypted guardian keys + CID) Pinata'ya yükle — mevcut IPFSManager API'sini kullan
3. Guardian key dağıtımı için relay server henüz yok. **Karar:** QR code ile manual paylaşım implement edilecek (guardian kullanıcıya QR gösterir, guardian tarar). Relay server ileride opsiyonel upgrade olarak eklenebilir
4. QR code: `CoreImage` CIQRCodeGenerator ile CID + encrypted key bundle encode edilecek

---

## Wave 2 — Architecture Refactoring + Test Coverage

### Track A — Refactoring

#### R1: WalletStore.swift Decomposition (1,248 satır → 5-6 modül)

**Current structure:** 30+ observable property, 25+ method, 6 farklı sorumluluk alanı tek dosyada.

**Proposed split:**

| New File | Responsibility | Lines from WalletStore | Key Properties/Methods |
|----------|---------------|----------------------|----------------------|
| `AccountManager.swift` | Account CRUD, passkey creation, deployment | 826-1060 | `accounts`, `activeAccountIndex`, `createPasskeyAccount()`, `deployActiveAccount()`, `deleteAccount()`, `reRegisterAccount()` |
| `TokenManager.swift` | Token balance fetching, custom tokens, NFTs | 517-653, 203-224 | `tokens`, `customTokens`, `nfts`, `fetchBalances()`, `fetchBalancesViaPXE()`, `registerTokenIfNeeded()` |
| `NetworkManager.swift` | Connection, network switching, node info | 493-513, 193-196 | `connected`, `network`, `nodeUrl`, `nodeInfo`, `checkConnection()`, `switchNetwork()` |
| `PersistenceManager.swift` | All UserDefaults/Keychain read/write | 1062-1138, 271-287 | `loadFromStorage()`, `saveAccounts()`, `saveConfig()`, `saveCustomTokens()`, etc. |
| `GuardianManager.swift` | Guardian recovery state, notifications | 677-729, 264-265 | `guardianStatus`, `guardians`, `checkGuardianStatus()`, `scheduleRecoveryNotification()` |
| `WalletStore.swift` (slim) | Orchestration, navigation, UI state, DI container | 189-260 remaining | `screen`, `toast`, `loading`, `pxeState`, references to managers |

**Approach:**
- `WalletStore` @Observable kalır, ama manager'ları property olarak tutar
- Manager'lar `@Observable` class olarak tanımlanır
- SwiftUI view'lar `@Environment(WalletStore.self)` yerine ihtiyaç duydukları manager'a erişir
- Migration incremental: önce extract, sonra view'ları güncelle

**Risk:** SwiftUI view'ların `WalletStore`'a doğrudan eriştiği 50+ yer var. Her birini güncellemek gerekecek.

**Mitigation:** İlk aşamada WalletStore computed property'leri ile backward compatibility sağla:
```swift
// WalletStore.swift (slim)
var accounts: [Account] { accountManager.accounts }
var tokens: [Token] { tokenManager.tokens }
// ... vs
```
Bu sayede view'lar kademeli olarak migrate edilebilir.

#### R2: PXEBridge.swift Decomposition (881 satır → 3-4 modül)

**Current structure:** WebView setup, IPC infra, 35+ API wrapper, message handling, native prover, storage shim hepsi bir arada.

**Proposed split:**

| New File | Responsibility | Lines from PXEBridge |
|----------|---------------|---------------------|
| `PXEWebViewManager.swift` | WebView lifecycle, setup, navigation delegate | 45-206, 855-865 |
| `PXEMessageBus.swift` | sendMessage, continuation management, timeouts, evaluateJS | 28-41, 210-276 |
| `PXENativeProver.swift` | Swoirenberg bridge, SRS setup, Chonk pipeline | 652-850 |
| `PXEBridge.swift` (slim) | Public API methods (thin wrappers) + message routing | 280-511, 517-647 |

**Approach:**
- `PXEMessageBus` protocol'ü extract et — testability için mock'lanabilir
- `PXENativeProver` tamamen bağımsız — kendi state'i var (SRS loaded, circuits cached)
- `PXEWebViewManager` WKWebView lifecycle'ı yönetir, `PXEMessageBus`'a delegate eder
- Storage shim (573-620) `PXEStorageShim.swift` olarak ayrılabilir (küçük, opsiyonel)

#### R3: Inpage Provider — Listener Registry

**File:** `extension/public/src/inpage.js`

**Problem:** S1'deki fix'in ötesinde, `on()` metodu bir `off()` companion'ı da olmalı (standart EventEmitter pattern).

**Fix:** S1'de yapılan unsubscribe return'ü yeterli. Ek olarak:
```javascript
off(event, handler) {
  // handler = on() tarafından döndürülen unsubscribe function
  if (typeof handler === 'function') handler();
},
```

---

### Track B — Test Coverage

#### T1: Bridge SDK Integration Tests

**Directory:** `bridge/sdk/__tests__/` (yeni)

**Scope:**
- `L1Client` — mock ethers provider ile deposit/withdraw flow
- `L2Client` — mock Aztec PXE ile claimPublic/claimPrivate flow
- `BridgeClient` — orchestration testi (L1 → L2 full cycle mock)
- `ContentHash` — IPFS CID calculation unit test

**Framework:** Jest (mevcut altyapı)

**Estimated:** 4-5 test dosyası, ~400 satır

#### T2: P256 Signature Verification Test

**File:** `contracts/celari_passkey_account/src/test.nr`

**Current state:** `// TODO: Test is_valid_impl (P256 signature verification)`

**Design:**
- Bilinen bir P256 key pair ile test signature oluştur
- `is_valid_impl` fonksiyonunu bu signature ile çağır
- Valid ve invalid case'leri test et
- TXE (Test Execution Environment) gerektirebilir — availability kontrol et

#### T3: WalletStore Unit Tests (Post-Refactoring)

**Directory:** `ios/CelariWalletTests/`

**Current state:** Sadece 3 trivial test var (23 satır).

**Design (R1 refactoring sonrasına bağlı):**

| Test File | Coverage |
|-----------|----------|
| `AccountManagerTests.swift` | Account CRUD, key generation, deployment mock |
| `TokenManagerTests.swift` | Balance fetching, custom token add/remove |
| `NetworkManagerTests.swift` | Connection check, network switch |
| `PersistenceManagerTests.swift` | UserDefaults round-trip, Keychain mock |
| `GuardianManagerTests.swift` | Status check, notification scheduling |

**Approach:**
- `PXEBridge` protocol'ü ile mock injection
- `UserDefaults(suiteName:)` ile izole test storage
- Async test support: `XCTestExpectation` veya Swift Testing `#expect`

#### T4: Guardian Recovery E2E Test

**File:** `contracts/celari_recoverable_account/src/test.nr`

**Current state:** `// TODO: Full integration tests require TestEnvironment (TXE)`

**Design:**
- TXE availability'ye bağlı
- Full flow: setup guardians → initiate recovery → wait cooldown → execute recovery
- TXE yoksa: unit test seviyesinde `is_guardian_configured`, `get_recovery_cid` test edilebilir

---

## Wave 3 — Performance + Final Touches

#### P1: offscreen.js Tree-Shaking

**Current:** 64 MB bundle (Aztec SDK tamamı)

**Approach:**
1. esbuild `treeShaking: true` zaten aktif olmalı — kontrol et
2. Kullanılmayan Aztec modüllerini analiz et (`@aztec/simulator` gibi büyük paketler)
3. Dynamic import ile bridge SDK'yı lazy load et (ayrı chunk)
4. Hedef: %20-30 küçülme (64 MB → ~45-50 MB)

**Risk:** Aztec SDK'nın internal circular dependency'leri tree-shaking'i engelleyebilir. Bu durumda manual exclusion gerekir.

#### P2: PXE Lazy Initialization

**Current state:** Mevcut roadmap (Phase 1.3) zaten bunu planlamış.

**Design:**
- PXE init'i app launch'tan ayır
- İlk wallet işlemi gerektiğinde init et
- Splash screen yerine "Connecting..." state göster
- Snapshot restore ile cold start süresini azalt (zaten implement edilmiş, line 478)

**Ek iyileştirme:** Incremental sync — son sync'ten bu yana sadece yeni block'ları sync et. `PXEPersistenceManager.getLastSyncedBlock()` zaten mevcut.

#### P3: Bridge SDK Lazy Loading

**File:** `extension/build.mjs`

**Design:** Bridge SDK'yı ana offscreen bundle'dan ayır. Kullanıcı bridge işlemi yapmadığı sürece yüklenmez.

```javascript
// offscreen.js'de:
// Before: import { BridgeClient } from '../bridge/sdk/bridge-client';
// After: const { BridgeClient } = await import('../bridge/sdk/bridge-client');
```

esbuild `splitting: true` + `format: "esm"` ile otomatik code splitting.

#### P4: Code Coverage Report Setup

**File:** `jest.config.ts`

**Design:**
```typescript
// jest.config.ts'e ekle:
collectCoverage: true,
coverageDirectory: "coverage",
coverageReporters: ["text", "lcov"],
coverageThreshold: {
  global: {
    branches: 50,
    functions: 60,
    lines: 60,
    statements: 60,
  },
},
```

Threshold'lar mevcut test coverage'a göre ayarlanacak — önce `--coverage` ile baseline ölç.

#### P5: Dead Code Cleanup

- `extension/src/` dizini varsa sil (manifest `public/src/` kullanıyor)
- Kullanılmayan import'ları temizle (ESLint `no-unused-vars` zaten aktif)
- `backup-before-fixes/` dizini git'e eklenmemeli — `.gitignore`'a ekle

---

## Dependency Graph

```
Wave 1 (parallel tracks):
  Track A: S1 → S2 → S3 → S4 → S5
  Track B: F1 → F2 → F3

Wave 2 (parallel tracks, Wave 1 bitmeli):
  Track A: R1 → R2 → R3
  Track B: T1 → T2 (T3 depends on R1, T4 depends on T2)

Wave 3 (Wave 2 bitmeli):
  P1 → P2 → P3 → P4 → P5
```

**Critical path:** Wave 1 → R1 (WalletStore refactoring) → T3 (unit tests) → Wave 3

---

## Success Criteria

| Metric | Current | Target |
|--------|---------|--------|
| Security issues (medium+) | 4 | 0 |
| WalletStore.swift lines | 1,248 | <300 (orchestration only) |
| PXEBridge.swift lines | 881 | <400 (API wrappers only) |
| iOS test count | 3 | 25+ |
| Bridge SDK test count | 0 | 15+ |
| offscreen.js bundle size | 64 MB | <50 MB |
| Event listener leaks | Yes | No |
| Code coverage (TypeScript) | Unknown | >60% |

---

## Out of Scope

- Yeni feature development (DEX UI, push notifications, WalletConnect v2 full integration) — bunlar roadmap Phase 3-4'te
- Swoirenberg native prover stabilization — ayrı track (roadmap Track 2)
- Mainnet deployment — roadmap Phase 5
- App Store submission process
- CI/CD pipeline setup
