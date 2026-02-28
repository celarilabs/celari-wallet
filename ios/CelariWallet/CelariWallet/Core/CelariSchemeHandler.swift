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

        // Resolve the actual file name to look up in the bundle.
        // WASM imports use relative URLs: new URL('file.wasm', import.meta.url)
        // With import.meta.url = "celari://offscreen.js", this resolves to
        // "celari://offscreen.js/file.wasm" where host="offscreen.js", path="/file.wasm".
        // All bundle resources are flat, so fall back to the last path component.
        let resolvedName: String
        if fileName.contains("/") {
            resolvedName = (fileName as NSString).lastPathComponent
        } else {
            resolvedName = fileName
        }

        let name = (resolvedName as NSString).deletingPathExtension
        let ext = (resolvedName as NSString).pathExtension

        // Serve raw files from bundle (gzip Content-Encoding removed — WKWebView's
        // ESM module loader doesn't reliably decompress gzip from custom URL schemes,
        // causing intermittent SyntaxError on first load).
        var data: Data
        if let fileURL = Bundle.main.url(forResource: name, withExtension: ext),
           let fileData = try? Data(contentsOf: fileURL) {
            data = fileData
        } else {
            schemeLog.error("[SchemeHandler] File not found: \(fileName, privacy: .public) (resolved: \(resolvedName, privacy: .public))")
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }

        let mimeType = Self.mimeType(for: ext)

        // CORS headers required for <script type="module"> on custom schemes
        let headers: [String: String] = [
            "Content-Type": mimeType,
            "Content-Length": "\(data.count)",
            "Access-Control-Allow-Origin": "*",
        ]

        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!

        let served = fileName.contains("/") ? "\(fileName) → \(resolvedName)" : fileName
        schemeLog.notice("[SchemeHandler] Serving \(served, privacy: .public) (\(data.count) bytes)")
        urlSchemeTask.didReceive(response as URLResponse)
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
