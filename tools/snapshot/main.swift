import AppKit
import WebKit

/// Renders a Markdown file through the app's own converter and stylesheet and
/// writes a PNG, so the README images always match what the app displays.
///
///     snapshot <input.md> <output.png> [dark] [width] [height]
final class Shooter: NSObject, WKNavigationDelegate {
    let web: WKWebView
    let out: URL
    var done = false

    init(markdown: String, base: URL, out: URL, dark: Bool, size: NSSize) {
        self.out = out
        web = WKWebView(frame: NSRect(origin: .zero, size: size), configuration: WKWebViewConfiguration())
        web.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        super.init()
        web.navigationDelegate = self
        let page = """
            <!doctype html><html><head><meta charset="utf-8">
            <style>\(Style.css)</style></head>
            <body><article>\(Markdown.html(from: markdown))</article></body></html>
            """
        web.loadHTMLString(PreviewRender.inlineImages(in: page, relativeTo: base), baseURL: base)
    }

    func webView(_ webView: WKWebView, didFinish nav: WKNavigation!) {
        // Give the web view a beat to lay out fonts and images before capturing.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            let config = WKSnapshotConfiguration()
            config.rect = CGRect(origin: .zero, size: webView.frame.size)
            webView.takeSnapshot(with: config) { image, _ in
                defer { self.done = true }
                guard let image, let tiff = image.tiffRepresentation,
                      let rep = NSBitmapImageRep(data: tiff),
                      let png = rep.representation(using: .png, properties: [:]) else { return }
                try? png.write(to: self.out)
            }
        }
    }
}

let args = CommandLine.arguments
guard args.count >= 3 else { fputs("usage: snapshot <in.md> <out.png> [dark] [w] [h]\n", stderr); exit(1) }
let dark = args.count > 3 && args[3] == "dark"
let w = args.count > 4 ? Double(args[4]) ?? 900 : 900
let h = args.count > 5 ? Double(args[5]) ?? 1000 : 1000
let input = URL(fileURLWithPath: args[1])
let text = (try? String(contentsOf: input, encoding: .utf8)) ?? ""

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let shooter = Shooter(markdown: text, base: input.deletingLastPathComponent(),
                      out: URL(fileURLWithPath: args[2]), dark: dark,
                      size: NSSize(width: w, height: h))
let deadline = Date().addingTimeInterval(20)
while !shooter.done && Date() < deadline {
    RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
}
