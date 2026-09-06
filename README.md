# Markdown

A minimal macOS Markdown previewer. Open a `.md` file, read it. No options.

- `⌘O`, or drag a file onto the window, to open
- Re-renders automatically when the file changes on disk, preserving scroll position
- `⌘P` exports the whole document as a PDF
- Light and dark mode follow the system
- Links open in your browser; links to other `.md` files open in the preview

No dependencies: the Markdown parser is ~350 lines of Swift, and rendering is a `WKWebView`.
Supports headings, nested and ordered lists, task lists, tables with alignment, fenced
code blocks, blockquotes, rules, images, links, and the usual inline emphasis.

## Build

```
./build.sh
```

Produces `Markdown.app` in this folder. Move it to `/Applications` if you like.
Requires the Xcode Command Line Tools; no Xcode needed.
