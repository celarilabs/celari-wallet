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
