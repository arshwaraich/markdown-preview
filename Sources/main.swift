import AppKit
import WebKit
import UniformTypeIdentifiers

// MARK: - Web view that renders one Markdown file

final class PreviewView: WKWebView, WKNavigationDelegate {
    private var current: URL?
    private var watcher: DispatchSourceFileSystemObject?

    var hasDocument: Bool { current != nil }

    init() {
        let config = WKWebViewConfiguration()
        super.init(frame: .zero, configuration: config)
        navigationDelegate = self
        setValue(false, forKey: "drawsBackground")
        registerForDraggedTypes([.fileURL])
        render(body: "<div class=\"empty\">Open a Markdown file<br><span>⌘O, or drop one here</span></div>")
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit { watcher?.cancel() }

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
        <style>\(Style.css)</style></head>
        <body><article>\(body)</article>
        <script>window.scrollTo(0, \(scrollTo));</script>
        </body></html>
        """
        let dir = base?.deletingLastPathComponent()
        loadHTMLString(dir.map { PreviewRender.inlineImages(in: page, relativeTo: $0) } ?? page,
                       baseURL: dir)
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
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var windows: [NSWindow] = []
    private var cascadePoint = NSPoint.zero

    func applicationDidFinishLaunching(_ note: Notification) {
        buildMenu()
        if windows.isEmpty { makeWindow() }
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ sender: NSApplication, openFile path: String) -> Bool {
        open(URL(fileURLWithPath: path))
        return true
    }

    func application(_ app: NSApplication, open urls: [URL]) {
        for url in urls { open(url) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        windows.removeAll { $0 === window }
    }

    // Creates a new, empty window. The first window uses the saved frame
    // from last launch; later ones cascade so they don't stack exactly.
    @discardableResult
    private func makeWindow() -> NSWindow {
        let preview = PreviewView()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "Markdown"
        window.contentView = preview
        window.delegate = self
        if windows.isEmpty {
            window.center()
            window.setFrameAutosaveName("MarkdownPreviewWindow")
        } else {
            cascadePoint = window.cascadeTopLeft(from: cascadePoint)
        }
        windows.append(window)
        window.makeKeyAndOrderFront(nil)
        return window
    }

    // Loads a file into the key window if it's still empty, into any other
    // empty window if not, or opens a fresh window otherwise. This is what
    // lets ⌘O build up multiple windows without leaving blank ones behind.
    private func open(_ url: URL) {
        let target: NSWindow
        if let key = NSApp.keyWindow, (key.contentView as? PreviewView)?.hasDocument == false {
            target = key
        } else if let empty = windows.first(where: { ($0.contentView as? PreviewView)?.hasDocument == false }) {
            target = empty
        } else {
            target = makeWindow()
        }
        (target.contentView as? PreviewView)?.load(url)
        target.makeKeyAndOrderFront(nil)
    }

    @objc func newWindow(_ sender: Any?) {
        makeWindow()
    }

    @objc func exportPDF(_ sender: Any?) {
        (NSApp.keyWindow?.contentView as? PreviewView)?.exportPDF()
    }

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText,
                                     UTType(filenameExtension: "markdown") ?? .plainText,
                                     .plainText]
        panel.allowsOtherFileTypes = true
        panel.allowsMultipleSelection = true
        panel.begin { [weak self] response in
            guard response == .OK, let self else { return }
            for url in panel.urls { self.open(url) }
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
        fileMenu.addItem(withTitle: "New Window", action: #selector(newWindow(_:)), keyEquivalent: "n")
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
