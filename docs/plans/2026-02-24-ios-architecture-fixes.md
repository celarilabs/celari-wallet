# iOS Architecture Fixes Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Remove private API usage, debug deploy hang, optimize bundle size, and add Dynamic Type support for Celari Wallet iOS.

**Architecture:** Four sequential tasks — WKURLSchemeHandler replaces file:// loading with custom celari:// scheme, deploy hang is debugged with granular JS logging visible in Xcode, bundle is gzip-served through the same scheme handler, and Dynamic Type is added to body text fonts only.

**Tech Stack:** Swift/SwiftUI (iOS 17+), WKWebView, esbuild, Aztec SDK (JS/WASM)

---

### Task 1: WKURLSchemeHandler — `celari://` Custom Scheme

**Files:**
- Create: `ios/CelariWallet/CelariWallet/Core/CelariSchemeHandler.swift`
- Modify: `ios/CelariWallet/CelariWallet/Core/PXEBridge.swift:52-53,117-120`
- Modify: `ios/CelariWallet/CelariWallet/Resources/pxe-bridge.html:41`
- Modify: `ios/CelariWallet/CelariWallet/Resources/pxe-bridge-shim.js:42-74`

**Step 1: Create `CelariSchemeHandler.swift`**

Create new file at `ios/CelariWallet/CelariWallet/Core/CelariSchemeHandler.swift`:

```swift
import WebKit
import os.log

private let schemeLog = Logger(subsystem: "com.celari.wallet", category: "SchemeHandler")

final class CelariSchemeHandler: NSObject, WKURLSchemeHandler {

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        let url = urlSchemeTask.request.url!
        // celari://offscreen.js -> path = "offscreen.js"
        // celari://pxe-bridge.html -> path = "pxe-bridge.html"
        let fileName: String
        if let host = url.host(percentEncoded: false), !host.isEmpty {
            // celari://file.ext -> host is "file.ext", path is empty or "/"
            fileName = host + url.path(percentEncoded: false)
        } else {
            fileName = String(url.path(percentEncoded: false).dropFirst()) // remove leading /
        }

        let name = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension

        guard let fileURL = Bundle.main.url(forResource: name, withExtension: ext) else {
            schemeLog.error("[SchemeHandler] File not found: \(fileName, privacy: .public)")
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }

        guard let data = try? Data(contentsOf: fileURL) else {
            schemeLog.error("[SchemeHandler] Cannot read: \(fileName, privacy: .public)")
            urlSchemeTask.didFailWithError(URLError(.cannotOpenFile))
            return
        }

        let mimeType = Self.mimeType(for: ext)
        let response = URLResponse(
            url: url,
            mimeType: mimeType,
            expectedContentLength: data.count,
            textEncodingName: mimeType.hasPrefix("text/") ? "utf-8" : nil
        )

        schemeLog.notice("[SchemeHandler] Serving \(fileName, privacy: .public) (\(data.count) bytes, \(mimeType, privacy: .public))")
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        // All responses are synchronous from bundle -- nothing to cancel
    }

    private static func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "html":  return "text/html"
        case "js":    return "text/javascript"
        case "mjs":   return "text/javascript"
        case "wasm":  return "application/wasm"
        case "json":  return "application/json"
        case "css":   return "text/css"
        default:      return "application/octet-stream"
        }
    }
}
```

**Step 2: Modify `PXEBridge.swift` -- replace private API with scheme handler**

In `PXEBridge.swift`, replace line 53:

```swift
// REMOVE this line:
config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

// ADD this line in its place:
config.setURLSchemeHandler(CelariSchemeHandler(), forURLScheme: "celari")
```

Then replace lines 117-120 (the loadFileURL block):

```swift
// REMOVE:
if let htmlURL = Bundle.main.url(forResource: "pxe-bridge", withExtension: "html") {
    wv.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
}

// REPLACE WITH:
wv.load(URLRequest(url: URL(string: "celari://pxe-bridge.html")!))
```

**Step 3: Update `pxe-bridge.html` -- use celari:// for module src**

In `pxe-bridge.html`, replace line 41:

```html
<!-- REMOVE: -->
<script type="module" src="offscreen.js"></script>

<!-- REPLACE WITH: -->
<script type="module" src="celari://offscreen.js"></script>
```

**Step 4: Update `pxe-bridge-shim.js` -- extend fetch polyfill to celari:// scheme**

WKURLSchemeHandler intercepts `celari://` requests made via `<script src>`, `<link href>`, and direct navigation -- but **not** `fetch()` or `XMLHttpRequest`. We must route those through the scheme handler too.

In `pxe-bridge-shim.js`, replace the fetch polyfill (lines 38-74):

```javascript
  // --- fetch() polyfill for celari:// and file:// URLs ---
  // WKURLSchemeHandler handles celari:// for <script src> and navigation,
  // but fetch() needs XMLHttpRequest to route through the scheme handler.
  var _origFetch = window.fetch;
  window.fetch = function(input, init) {
    var url = (input instanceof Request) ? input.url : String(input);
    if (url.startsWith('celari://') || url.startsWith('file://')) {
      return new Promise(function(resolve, reject) {
        var xhr = new XMLHttpRequest();
        xhr.open('GET', url, true);
        xhr.responseType = 'arraybuffer';
        xhr.onload = function() {
          if (xhr.status === 0 || (xhr.status >= 200 && xhr.status < 300)) {
            var mime = 'application/octet-stream';
            if (url.endsWith('.wasm')) mime = 'application/wasm';
            else if (url.endsWith('.js')) mime = 'application/javascript';
            else if (url.endsWith('.json')) mime = 'application/json';
            else if (url.endsWith('.html')) mime = 'text/html';
            resolve(new Response(xhr.response, {
              status: 200,
              statusText: 'OK',
              headers: { 'Content-Type': mime }
            }));
          } else {
            reject(new Error('XHR failed: ' + xhr.status + ' for ' + url));
          }
        };
        xhr.onerror = function() {
          reject(new Error('XHR error loading ' + url));
        };
        xhr.send();
      });
    }
    return _origFetch.apply(this, arguments);
  };
  console.log('[PXE-Shim] fetch() polyfill for celari:// and file:// URLs installed');
```

**Step 5: Build and verify**

Run:
```bash
cd /Volumes/huseyin/celari-wallet-main/ios/CelariWallet && xcodebuild -scheme CelariWallet -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5
```
Expected: `BUILD SUCCEEDED`

**Step 6: Commit**

```bash
cd /Volumes/huseyin/celari-wallet-main
git add ios/CelariWallet/CelariWallet/Core/CelariSchemeHandler.swift \
        ios/CelariWallet/CelariWallet/Core/PXEBridge.swift \
        ios/CelariWallet/CelariWallet/Resources/pxe-bridge.html \
        ios/CelariWallet/CelariWallet/Resources/pxe-bridge-shim.js
git commit -m "feat(ios): replace allowFileAccessFromFileURLs with WKURLSchemeHandler

Implement celari:// custom URL scheme to serve bundle resources
without using the private WebKit API. This resolves App Store
review risk from private API usage.

- Add CelariSchemeHandler with MIME type detection
- Update PXEBridge to use celari:// scheme for WKWebView loading
- Update pxe-bridge.html script src to celari://
- Extend fetch polyfill to intercept celari:// URLs"
```

---

### Task 2: Deploy Hang -- Granular Debug Logging

**Files:**
- Modify: `extension/public/src/offscreen.js:219-230,733-817`

**Step 1: Add granular logging to `setupSponsoredFPC()`**

In `offscreen.js`, replace `setupSponsoredFPC` function (lines 219-230):

```javascript
async function setupSponsoredFPC(walletInstance) {
  console.log("[PXE] SponsoredFPC: Step 2a -- importing SponsoredFPCContract artifact...");
  const t2a = Date.now();
  const { SponsoredFPCContract } = await import("@aztec/noir-contracts.js/SponsoredFPC");
  console.log(`[PXE] SponsoredFPC: Step 2a OK (${Date.now() - t2a}ms)`);

  console.log("[PXE] SponsoredFPC: Step 2b -- getContractInstanceFromInstantiationParams (WASM)...");
  const t2b = Date.now();
  const fpcInstance = await getContractInstanceFromInstantiationParams(
    SponsoredFPCContract.artifact,
    { salt: new Fr(0) },
  );
  console.log(`[PXE] SponsoredFPC: Step 2b OK (${Date.now() - t2b}ms)`);

  console.log("[PXE] SponsoredFPC: Step 2c -- registerContract...");
  const t2c = Date.now();
  await walletInstance.registerContract(fpcInstance, SponsoredFPCContract.artifact);
  console.log(`[PXE] SponsoredFPC: Step 2c OK (${Date.now() - t2c}ms)`);

  return {
    instance: fpcInstance,
    paymentMethod: new SponsoredFeePaymentMethod(fpcInstance.address),
  };
}
```

**Step 2: Add granular logging to `deployAccountClientSide()`**

In `offscreen.js`, replace the `deployAccountClientSide` function (lines 733-817). Keep identical logic, add logging around every async boundary:

```javascript
async function deployAccountClientSide(data) {
  console.log(`[PXE] >>> deployAccountClientSide ENTERED`);
  if (!wallet) throw new Error("PXE not initialized");

  const { publicKeyX, publicKeyY, privateKeyPkcs8 } = data;
  console.log(`[PXE] pubKeyX: ${publicKeyX?.slice(0,16)}..., pkcs8: ${privateKeyPkcs8 ? 'present' : 'MISSING'}`);

  const secretKey = Fr.random();
  const salt = Fr.random();

  const accountContract = new BrowserCelariPasskeyAccountContract(
    hexToBuffer(publicKeyX),
    hexToBuffer(publicKeyY),
    privateKeyPkcs8,
  );

  // Step 1: Create account
  console.log("[PXE] Deploy Step 1: wallet.createAccount()...");
  const t1 = Date.now();
  let manager;
  try {
    manager = await Promise.race([
      wallet.createAccount({ secret: secretKey, salt, contract: accountContract }),
      new Promise((_, rej) => setTimeout(() => rej(new Error("createAccount timed out after 3 min")), 180000)),
    ]);
    console.log(`[PXE] Deploy Step 1: OK (${Date.now() - t1}ms) -- address: ${manager.address.toString().slice(0, 22)}...`);
  } catch (e) {
    console.error(`[PXE] Deploy Step 1: FAILED (${Date.now() - t1}ms) -- ${e.message}`);
    throw e;
  }

  const address = manager.address;

  // Step 2: SponsoredFPC
  console.log("[PXE] Deploy Step 2: setupSponsoredFPC...");
  const t2 = Date.now();
  let paymentMethod;
  try {
    const fpc = await Promise.race([
      setupSponsoredFPC(wallet),
      new Promise((_, rej) => setTimeout(() => rej(new Error("setupSponsoredFPC timed out after 3 min")), 180000)),
    ]);
    paymentMethod = fpc.paymentMethod;
    console.log(`[PXE] Deploy Step 2: OK (${Date.now() - t2}ms)`);
  } catch (e) {
    console.error(`[PXE] Deploy Step 2: FAILED (${Date.now() - t2}ms) -- ${e.message}`);
    throw e;
  }

  // Step 3: getDeployMethod
  console.log("[PXE] Deploy Step 3: getDeployMethod...");
  const t3 = Date.now();
  const deployMethod = await manager.getDeployMethod();
  console.log(`[PXE] Deploy Step 3: OK (${Date.now() - t3}ms)`);

  // Patch: force external fee path
  const _origConvert = deployMethod.convertDeployOptionsToRequestOptions.bind(deployMethod);
  deployMethod.convertDeployOptionsToRequestOptions = (opts) => {
    const r = _origConvert(opts);
    r.deployer = undefined;
    return r;
  };

  // Step 4: send
  console.log("[PXE] Deploy Step 4: deployMethod.send()...");
  const t4 = Date.now();
  const sentTx = deployMethod.send({
    from: AztecAddress.ZERO,
    fee: { paymentMethod },
  });
  console.log(`[PXE] Deploy Step 4: send() returned (${Date.now() - t4}ms)`);

  // Step 5: getTxHash
  console.log("[PXE] Deploy Step 5: getTxHash...");
  const t5 = Date.now();
  const txHash = await sentTx.getTxHash();
  console.log(`[PXE] Deploy Step 5: txHash: ${txHash.toString().slice(0, 22)}... (${Date.now() - t5}ms)`);

  // Step 6: wait for inclusion
  console.log("[PXE] Deploy Step 6: waiting for block inclusion (timeout 7 min)...");
  const t6 = Date.now();
  const receipt = await sentTx.wait({ timeout: 420_000 });
  console.log(`[PXE] Deploy Step 6: Deployed! Block ${receipt.blockNumber} (${Date.now() - t6}ms total)`);

  // Store in multi-account map
  const addrStr = address.toString();
  const acctWallet = new Proxy(wallet, {
    get(target, prop) {
      if (prop === 'getAddress') {
        return () => AztecAddress.fromString(addrStr);
      }
      const val = target[prop];
      return typeof val === 'function' ? val.bind(target) : val;
    }
  });
  accountWallets.set(addrStr, { manager, wallet: acctWallet });
  activeAddress = addrStr;

  return {
    address: addrStr,
    secretKey: secretKey.toString(),
    salt: salt.toString(),
    txHash: txHash.toString(),
    blockNumber: receipt.blockNumber?.toString() || "",
  };
}
```

**Step 3: Rebuild offscreen.js for iOS**

Run:
```bash
cd /Volumes/huseyin/celari-wallet-main && node extension/build.mjs --ios
```
Expected: `Pass 3: iOS offscreen bundle OK`

Note: This requires `node_modules` to be installed. If not available, run `npm install` first at the repo root.

**Step 4: Build iOS and verify**

Run:
```bash
cd /Volumes/huseyin/celari-wallet-main/ios/CelariWallet && xcodebuild -scheme CelariWallet -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5
```
Expected: `BUILD SUCCEEDED`

**Step 5: Test on Simulator -- observe Xcode Console**

1. Run app on Simulator from Xcode
2. Create account (triggers deploy)
3. In Xcode Console, filter: `PXE`
4. Document which step hangs (last "Step N: ..." log without corresponding "OK")

**Step 6: Commit**

```bash
cd /Volumes/huseyin/celari-wallet-main
git add extension/public/src/offscreen.js
git commit -m "debug(ios): add granular deploy logging to offscreen.js

Break deployAccountClientSide and setupSponsoredFPC into
individually-timed steps with timeout guards. Each step logs
to console which is captured by Swift PXEBridge jsConsole
handler, making deploy hang diagnosis possible in Xcode Console."
```

**Step 7: Diagnose and fix based on findings**

This is an interactive step. After observing which step hangs:

- If Step 1 (`createAccount`) hangs: investigate contract artifact registration in MemoryAztecStore
- If Step 2b (`getContractInstanceFromInstantiationParams`) hangs: WASM op failing, check SchemeHandler serves `.wasm` correctly
- If Step 4/5 (`send`/`getTxHash`) hangs: proving issue, check Barretenberg WASM initialization
- If Step 6 (`wait`) hangs: network/node issue, check connectivity

---

### Task 3: Bundle Optimization -- Gzip Serving

**Files:**
- Modify: `ios/CelariWallet/CelariWallet/Core/CelariSchemeHandler.swift`
- Modify: `extension/build.mjs` (add post-build gzip step for iOS pass)

**Step 1: Add gzip support to `CelariSchemeHandler`**

Update `webView(_:start:)` in `CelariSchemeHandler.swift` to check for `.gz` variant first:

```swift
func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
    let url = urlSchemeTask.request.url!
    let fileName: String
    if let host = url.host(percentEncoded: false), !host.isEmpty {
        fileName = host + url.path(percentEncoded: false)
    } else {
        fileName = String(url.path(percentEncoded: false).dropFirst())
    }

    let name = (fileName as NSString).deletingPathExtension
    let ext = (fileName as NSString).pathExtension

    // Try gzip-compressed variant first (e.g., offscreen.js.gz for offscreen.js)
    var data: Data
    var isGzipped = false
    if let gzURL = Bundle.main.url(forResource: name, withExtension: ext + ".gz"),
       let gzData = try? Data(contentsOf: gzURL) {
        data = gzData
        isGzipped = true
    } else if let fileURL = Bundle.main.url(forResource: name, withExtension: ext),
              let fileData = try? Data(contentsOf: fileURL) {
        data = fileData
    } else {
        schemeLog.error("[SchemeHandler] File not found: \(fileName, privacy: .public)")
        urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
        return
    }

    let mimeType = Self.mimeType(for: ext)

    // Use HTTPURLResponse for gzip Content-Encoding header
    var headers: [String: String] = [
        "Content-Type": mimeType,
        "Content-Length": "\(data.count)"
    ]
    if isGzipped {
        headers["Content-Encoding"] = "gzip"
    }

    let response = HTTPURLResponse(
        url: url,
        statusCode: 200,
        httpVersion: "HTTP/1.1",
        headerFields: headers
    )!

    let label = isGzipped ? "gzip" : "raw"
    schemeLog.notice("[SchemeHandler] Serving \(fileName, privacy: .public) (\(data.count) bytes, \(label, privacy: .public))")
    urlSchemeTask.didReceive(response as URLResponse)
    urlSchemeTask.didReceive(data)
    urlSchemeTask.didFinish()
}
```

**Step 2: Add gzip post-build step to `build.mjs`**

In `extension/build.mjs`, after the iOS Pass 3 build completes (after line 164), add:

```javascript
    // Gzip large files for iOS SchemeHandler serving
    const { execFileSync } = await import("child_process");
    const iosFiles = ["offscreen.js"];
    for (const f of iosFiles) {
      const filePath = resolve(iosOutdir, f);
      if (existsSync(filePath)) {
        execFileSync("gzip", ["-k", "-f", "-9", filePath]);
        const { statSync } = await import("fs");
        const origSize = statSync(filePath).size;
        const gzSize = statSync(filePath + ".gz").size;
        const ratio = ((1 - gzSize / origSize) * 100).toFixed(1);
        console.log(`  Gzip: ${f} -- ${(origSize / 1048576).toFixed(1)}MB -> ${(gzSize / 1048576).toFixed(1)}MB (${ratio}% reduction)`);
      }
    }
```

**Step 3: Rebuild and verify**

Run:
```bash
cd /Volumes/huseyin/celari-wallet-main && node extension/build.mjs --ios
```
Expected: `Gzip: offscreen.js -- 69.0MB -> ~12-15MB (80%+ reduction)`

Then verify the `.gz` file:
```bash
ls -lh /Volumes/huseyin/celari-wallet-main/ios/CelariWallet/CelariWallet/Resources/offscreen.js.gz
```

**Step 4: Add `offscreen.js.gz` to Xcode project**

The `.gz` file must be in the app bundle. Add it to Xcode project's Copy Bundle Resources build phase (manual step in Xcode, or edit `project.pbxproj`).

**Step 5: Build iOS**

Run:
```bash
cd /Volumes/huseyin/celari-wallet-main/ios/CelariWallet && xcodebuild -scheme CelariWallet -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5
```
Expected: `BUILD SUCCEEDED`

**Step 6: Commit**

```bash
cd /Volumes/huseyin/celari-wallet-main
git add ios/CelariWallet/CelariWallet/Core/CelariSchemeHandler.swift \
        extension/build.mjs
git commit -m "perf(ios): serve offscreen.js gzip-compressed via SchemeHandler

Add gzip-aware serving to CelariSchemeHandler -- checks for .gz
variant first and sets Content-Encoding: gzip header. Add gzip
post-build step to build.mjs iOS pass. Reduces served JS from
~69MB to ~12-15MB, improving WKWebView parse time."
```

---

### Task 4: Dynamic Type -- Body Text Fonts

**Files:**
- Modify: `ios/CelariWallet/CelariWallet/Theme/CelariTheme.swift:59,62-63`
- Modify: `ios/CelariWallet/CelariWallet/Components/ToastOverlay.swift:31`

**Step 1: Update body and accent fonts with `relativeTo:`**

In `CelariTheme.swift`, replace the three font definitions:

```swift
// Line 59 -- REPLACE:
static let accent = Font.custom("TenorSans-Regular", size: 12)
// WITH:
static let accent = Font.custom("TenorSans-Regular", size: 12, relativeTo: .body)

// Line 62 -- REPLACE:
static let body = Font.custom("Outfit-Regular", size: 13)
// WITH:
static let body = Font.custom("Outfit-Regular", size: 13, relativeTo: .body)

// Line 63 -- REPLACE:
static let bodySmall = Font.custom("Outfit-Regular", size: 11)
// WITH:
static let bodySmall = Font.custom("Outfit-Regular", size: 11, relativeTo: .footnote)
```

**Step 2: Add overflow clamp to ToastOverlay**

In `ToastOverlay.swift`, add `.dynamicTypeSize(...:.xxxLarge)` after the `.transition` modifier (after line 31):

```swift
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .dynamicTypeSize(...:.xxxLarge)
        .animation(.easeInOut(duration: 0.25), value: toast.message)
```

**Step 3: Build and verify**

Run:
```bash
cd /Volumes/huseyin/celari-wallet-main/ios/CelariWallet && xcodebuild -scheme CelariWallet -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5
```
Expected: `BUILD SUCCEEDED`

**Step 4: Visual verification on Simulator**

1. Run app on Simulator from Xcode
2. Settings > Accessibility > Larger Text > drag slider to largest
3. Verify body text scales but mono/heading fonts stay fixed
4. Verify toast messages don't overflow screen

**Step 5: Commit**

```bash
cd /Volumes/huseyin/celari-wallet-main
git add ios/CelariWallet/CelariWallet/Theme/CelariTheme.swift \
        ios/CelariWallet/CelariWallet/Components/ToastOverlay.swift
git commit -m "a11y(ios): add Dynamic Type support for body text fonts

Enable relativeTo: scaling for body, bodySmall, and accent fonts.
Heading and mono fonts remain fixed for design consistency.
Add .dynamicTypeSize clamp on ToastOverlay to prevent overflow."
```
