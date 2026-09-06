import AppKit
import WebKit
import UniformTypeIdentifiers

// MARK: - Web view that renders one Markdown file

final class PreviewView: WKWebView, WKNavigationDelegate {
    private var current: URL?
    private var watcher: DispatchSourceFileSystemObject?

    init() {
        let config = WKWebViewConfiguration()
        super.init(frame: .zero, configuration: config)
        navigationDelegate = self
        setValue(false, forKey: "drawsBackground")
        registerForDraggedTypes([.fileURL])
        render(body: "<div class=\"empty\">Open a Markdown file<br><span>⌘O, or drop one here</span></div>")
    }

    required init?(coder: NSCoder) { fatalError() }

    func load(_ fileURL: URL) {
        current = fileURL
        window?.title = fileURL.lastPathComponent
        window?.representedURL = fileURL
        NSDocumentController.shared.noteNewRecentDocumentURL(fileURL)
        refresh()
        watch(fileURL)
    }

    private func refresh() {
        guard let url = current else { return }
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        // Keep the scroll position across live reloads.
        evaluateJavaScript("window.scrollY") { [weak self] y, _ in
            guard let self else { return }
            let offset = (y as? Double) ?? 0
            self.render(body: Markdown.html(from: text), scrollTo: offset, base: url)
        }
    }

    private func render(body: String, scrollTo: Double = 0, base: URL? = nil) {
        let page = """
        <!doctype html><html><head><meta charset="utf-8">
        <style>\(PreviewView.css)</style></head>
        <body><article>\(body)</article>
        <script>window.scrollTo(0, \(scrollTo));</script>
        </body></html>
        """
        loadHTMLString(page, baseURL: base?.deletingLastPathComponent())
    }

    // Re-render when the file changes on disk.
    private func watch(_ fileURL: URL) {
        watcher?.cancel()
        let fd = open(fileURL.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = source.data
            if flags.contains(.write) {
                self.refresh()
            } else if let url = self.current {
                // Editors that save by replacing the file need a fresh handle.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.refresh()
                    self.watch(url)
                }
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }

    /// Render the whole document (not just the visible part) to a PDF.
    func exportPDF() {
        guard let source = current else { NSSound.beep(); return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = source.deletingPathExtension().lastPathComponent + ".pdf"
        panel.allowedContentTypes = [.pdf]
        panel.begin { [weak self] response in
            guard response == .OK, let dest = panel.url, let self else { return }
            let config = WKPDFConfiguration()
            self.createPDF(configuration: config) { result in
                switch result {
                case .success(let data):
                    try? data.write(to: dest)
                case .failure(let error):
                    NSAlert(error: error).runModal()
                }
            }
        }
    }

    // Open links in the default browser instead of navigating the preview.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if action.navigationType == .linkActivated, let link = action.request.url {
            if link.isFileURL, ["md", "markdown", "mdown", "txt"].contains(link.pathExtension.lowercased()) {
                load(link)
            } else {
                NSWorkspace.shared.open(link)
            }
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    // MARK: Drag and drop

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        droppedURL(sender) != nil ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = droppedURL(sender) else { return false }
        load(url)
        return true
    }

    private func droppedURL(_ sender: NSDraggingInfo) -> URL? {
        guard let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
            let url = urls.first else { return nil }
        return url
    }

    static let css = """
    :root { color-scheme: light dark; }
    body {
      font: 16px/1.65 -apple-system, "SF Pro Text", "Helvetica Neue", sans-serif;
      margin: 0; color: #1d1d1f; background: #fff;
      -webkit-font-smoothing: antialiased;
    }
    article { max-width: 44rem; margin: 0 auto; padding: 3rem 2.5rem 6rem; }
    h1, h2, h3, h4, h5, h6 { line-height: 1.25; margin: 2em 0 .6em; font-weight: 600; }
    h1 { font-size: 2em; margin-top: 0; }
    h2 { font-size: 1.5em; padding-bottom: .3em; border-bottom: 1px solid rgba(127,127,127,.25); }
    h3 { font-size: 1.25em; } h4 { font-size: 1em; }
    h5, h6 { font-size: .9em; color: #6e6e73; }
    p, ul, ol, blockquote, table, pre { margin: 0 0 1.1em; }
    a { color: #0066cc; text-decoration: none; }
    a:hover { text-decoration: underline; }
    ul, ol { padding-left: 1.6em; }
    li { margin: .25em 0; }
    li > input[type=checkbox] { margin-right: .4em; }
    blockquote {
      margin-left: 0; padding: .1em 1em; color: #57606a;
      border-left: 3px solid rgba(127,127,127,.35);
    }
    code {
      font: .875em/1.5 ui-monospace, "SF Mono", Menlo, monospace;
      background: rgba(127,127,127,.14); padding: .15em .35em; border-radius: 4px;
    }
    pre {
      background: rgba(127,127,127,.11); padding: 1em; border-radius: 8px;
      overflow-x: auto;
    }
    pre code { background: none; padding: 0; font-size: .85em; }
    hr { border: 0; border-top: 1px solid rgba(127,127,127,.3); margin: 2em 0; }
    table { border-collapse: collapse; display: block; overflow-x: auto; }
    th, td { border: 1px solid rgba(127,127,127,.3); padding: .45em .8em; }
    th { background: rgba(127,127,127,.1); font-weight: 600; }
    img { max-width: 100%; border-radius: 6px; }
    .empty {
      position: fixed; inset: 0; display: flex; flex-direction: column;
      align-items: center; justify-content: center; gap: .5em;
      color: #8e8e93; font-size: 1.2em; text-align: center;
    }
    .empty span { font-size: .8em; opacity: .8; }
    @media (prefers-color-scheme: dark) {
      body { color: #e8e8ed; background: #1e1e1e; }
      h5, h6 { color: #98989d; }
      blockquote { color: #a1a1a6; }
      a { color: #4a9eff; }
    }
    """
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private let preview = PreviewView()

    func applicationDidFinishLaunching(_ note: Notification) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "Markdown"
        window.contentView = preview
        window.center()
        window.setFrameAutosaveName("MarkdownPreviewWindow")
        window.makeKeyAndOrderFront(nil)
        buildMenu()
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ sender: NSApplication, openFile path: String) -> Bool {
        preview.load(URL(fileURLWithPath: path))
        return true
    }

    func application(_ app: NSApplication, open urls: [URL]) {
        if let url = urls.first { preview.load(url) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }

    @objc func exportPDF(_ sender: Any?) {
        preview.exportPDF()
    }

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText,
                                     UTType(filenameExtension: "markdown") ?? .plainText,
                                     .plainText]
        panel.allowsOtherFileTypes = true
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.preview.load(url)
        }
    }

    private func buildMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Markdown", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Markdown", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Markdown", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Open…", action: #selector(openDocument(_:)), keyEquivalent: "o")
        let recents = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        let recentsMenu = NSMenu(title: "Open Recent")
        recentsMenu.perform(Selector(("_setMenuName:")), with: "NSRecentDocumentsMenu")
        recents.submenu = recentsMenu
        fileMenu.addItem(recents)
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Export as PDF…", action: #selector(exportPDF(_:)), keyEquivalent: "p")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileItem.submenu = fileMenu
        main.addItem(fileItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        viewMenu.items.last?.keyEquivalentModifierMask = [.command, .control]
        viewItem.submenu = viewMenu
        main.addItem(viewItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)

        NSApp.mainMenu = main
        NSApp.windowsMenu = windowMenu
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
