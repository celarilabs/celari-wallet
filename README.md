<p align="center">
  <img src="branding/celari-alt-logo.svg" alt="Celari" width="80" />
</p>

<h1 align="center">Celari</h1>

<p align="center">
  <strong>The first passkey-native privacy wallet on Aztec Network</strong><br/>
  <em>celāre (Latin) — to hide, to conceal, to keep secret</em>
</p>

<p align="center">
  <a href="https://celariwallet.com">Website</a> &middot;
  <a href="https://github.com/celarilabs/celari-wallet/issues">Issues</a> &middot;
  <a href="#contributing">Contributing</a>
</p>

---

Celari replaces seed phrases with biometric authentication — Face ID, fingerprint, Windows Hello — while leveraging Aztec's zero-knowledge architecture for complete transaction privacy. Built with **P256/secp256r1** signature verification in Noir circuits, it's the first wallet on Aztec to use WebAuthn/Passkey for account abstraction.

## Why Celari?

| | Traditional Wallets | Celari |
|-|-------------------|--------|
| **Authentication** | 24-word seed phrase | Face ID / Fingerprint |
| **Key storage** | Software (extractable) | Hardware secure enclave |
| **Backup** | Manual paper backup | iCloud / Google auto-sync |
| **Privacy** | Pseudonymous (traceable) | Fully private (ZK proofs) |
| **Phishing** | High risk | Domain-bound credentials |

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│  CLIENTS                                                            │
│                                                                     │
│  ┌─────────────────────┐    ┌────────────────────────────────────┐  │
│  │  iOS Native App     │    │  Chrome Extension (MV3)            │  │
│  │  SwiftUI + WKWebView│    │  popup + background + offscreen    │  │
│  │  Face ID / Touch ID │    │  WebAuthn Passkey                  │  │
│  │  Keychain P256      │    │  Secure Enclave P256               │  │
│  └──────────┬──────────┘    └──────────────────┬─────────────────┘  │
│             │                                  │                    │
│  ┌──────────▼──────────────────────────────────▼─────────────────┐  │
│  │         Shared PXE Layer (Private Execution Environment)      │  │
│  │                                                               │  │
│  │  MemoryAztecStore (serialize / deserialize)                   │  │
│  │  BrowserP256AuthWitnessProvider (WebCrypto ECDSA)             │  │
│  │  SponsoredFPC (gasless transactions)                          │  │
│  └──────────────────────────────┬────────────────────────────────┘  │
└─────────────────────────────────┼───────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Aztec Network                                                      │
│                                                                     │
│  CelariPasskeyAccount (Noir)                                        │
│  ├── ecdsa_secp256r1::verify_signature (P256 in ZK)                 │
│  ├── PublicKeyNote: custom Packable [u8;32] → 4 Fields              │
│  └── Auth witness: 64 Fr fields (r‖s signature bytes)               │
│                                                                     │
│  SponsoredFPC  ·  TokenContract  ·  Encrypted UTXOs                 │
└─────────────────────────────────────────────────────────────────────┘
```

## Platforms

**iOS Native App** — SwiftUI with 15+ screens, WKWebView PXE bridge, AES-256-GCM encrypted state persistence, Face ID / Touch ID authentication.

**Chrome Extension** — Manifest V3 with WebAuthn passkey signing, dApp provider API (`window.celari`), offscreen PXE client.

## Transfer Types

All four Aztec transfer modes are supported end-to-end on testnet:

| Type | Method | Description |
|------|--------|-------------|
| Public | `transfer_in_public()` | Standard transparent transfer |
| Private | `transfer()` | Fully private, zero on-chain metadata |
| Shield | `transfer_to_private()` | Move funds from public to private |
| Unshield | `transfer_to_public()` | Move funds from private to public |

All transfers use P256 auth witnesses verified by the Noir contract. Gasless execution via SponsoredFPC.

## Project Structure

```
celari-wallet/
├── contracts/celari_passkey_account/  # P256 Noir account contract
├── extension/                         # Chrome extension (MV3)
│   ├── public/src/                    # popup, background, content, inpage, offscreen
│   └── build.mjs                      # esbuild bundler
├── ios/CelariWallet/                  # iOS native app (SwiftUI)
│   └── CelariWallet/
│       ├── Core/                      # WalletStore, PXEBridge, Persistence
│       ├── Views/                     # 15+ SwiftUI screens
│       └── Models/                    # Account, Token, Activity models
├── sdk/                               # @celari/wallet-sdk package
├── src/
│   ├── utils/                         # Passkey utilities, P256 helpers
│   └── test/                          # Unit + E2E tests
└── scripts/                           # Deploy & token scripts
```

## Getting Started

### Prerequisites

- Node.js >= 22.15
- [Aztec Sandbox](https://docs.aztec.network) (for local development)
- Xcode 26+ (for iOS development)

### Build

```bash
yarn install
yarn build          # compile Noir contract + codegen
```

### Chrome Extension

```bash
yarn ext:build      # production build
# chrome://extensions → Developer mode → Load unpacked → extension/dist/
```

### Tests

```bash
yarn test           # unit + integration tests
yarn test:txe       # Noir contract tests (TXE)
```

## dApp Integration

```javascript
// Connect wallet
const { address } = await window.celari.connect();

// Send transaction
await window.celari.sendTransaction({
  to: "0x...",
  amount: 1000n,
  token: "CLR"
});

// Create auth witness
await window.celari.createAuthWit(messageHash);
```

## Why P256 Over secp256k1?

| | secp256k1 (Ethereum) | P256/secp256r1 (Celari) |
|-|---------------------|------------------------|
| Hardware support | None | Apple Secure Enclave, Android TEE, TPM 2.0 |
| WebAuthn/FIDO2 | Not compatible | Native standard |
| Key extraction | Possible | Impossible (hardware-bound) |
| Cross-device sync | Manual seed backup | Automatic via OS keychain |

## Roadmap

- [x] P256 Noir account contract
- [x] Chrome extension with WebAuthn
- [x] iOS native app with PXE bridge
- [x] All transfer types (public, private, shield, unshield)
- [x] Gasless transactions (SponsoredFPC)
- [x] 95 tests across 7 suites
- [ ] L1 ↔ L2 bridge integration
- [ ] App Store release
- [ ] Android native app
- [ ] WalletConnect v2
- [ ] Security audit & mainnet deployment

## Contributing

We welcome contributions. Please open an issue first to discuss what you'd like to change.

## License

This project is source-available under the [Business Source License 1.1](LICENSE.md). See the license file for details.

---

<p align="center">
  <strong>Celari</strong> — Your transactions speak zero.
</p>
