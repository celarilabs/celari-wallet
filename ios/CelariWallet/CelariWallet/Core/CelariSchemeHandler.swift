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
