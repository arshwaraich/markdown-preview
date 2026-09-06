# Markdown

A minimal previewer for macOS. Open a file, read it.

## Why

No settings, no sidebar, no mode switcher. It opens `.md` files and
renders them, and it re-renders the moment the file changes on disk.

> Everything should be made as simple as possible, but no simpler.

## What it handles

- **Emphasis**, *italics*, `inline code`, ~~strikethrough~~
- [Links](https://example.com) that open in your browser
- Task lists:
  - [x] Live reload on save
  - [x] Export to PDF with ⌘P
  - [ ] Anything else

1. Ordered lists
2. Nested content
3. Tables with alignment

| Feature      | Shortcut | Notes                  |
|:-------------|:--------:|-----------------------:|
| Open         | ⌘O       | or drop a file         |
| Export PDF   | ⌘P       | whole document         |
| Full screen  | ⌃⌘F      | —                      |

## Code

```swift
enum Markdown {
    static func html(from markdown: String) -> String {
        // ~350 lines, no dependencies
    }
}
```

---

Built with AppKit and `WKWebView`.
