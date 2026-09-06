import Foundation

/// Preparing generated HTML for display. Shared by the app and the screenshot
/// tool so both show a document the same way.
enum PreviewRender {
    /// WKWebView refuses to load local subresources for a page supplied as a
    /// string, so local images are embedded as data URIs instead. Remote ones
    /// are left alone for the browser to fetch.
    static func inlineImages(in html: String, relativeTo dir: URL) -> String {
        guard let re = try? NSRegularExpression(pattern: #"src=\"([^\"]+)\""#) else { return html }
        let ns = html as NSString
        var out = ""
        var last = 0
        for m in re.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let src = ns.substring(with: m.range(at: 1))
            out += embed(src, relativeTo: dir).map { "src=\"\($0)\"" } ?? ns.substring(with: m.range)
            last = m.range.location + m.range.length
        }
        return out + ns.substring(from: last)
    }

    private static func embed(_ src: String, relativeTo dir: URL) -> String? {
        guard !src.hasPrefix("data:"), URL(string: src)?.scheme == nil else { return nil }
        let decoded = src.removingPercentEncoding ?? src
        let file = decoded.hasPrefix("/") ? URL(fileURLWithPath: decoded)
                                          : dir.appendingPathComponent(decoded)
        guard let data = try? Data(contentsOf: file), data.count < 24_000_000 else { return nil }
        let types = ["png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg",
                     "gif": "image/gif", "svg": "image/svg+xml", "webp": "image/webp"]
        let mime = types[file.pathExtension.lowercased()] ?? "application/octet-stream"
        return "data:\(mime);base64,\(data.base64EncodedString())"
    }
}
