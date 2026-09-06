import Foundation

/// Stylesheet for the rendered preview. Shared by the app and the
/// screenshot tool so the images in the README match what ships.
enum Style {
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
li:has(> input[type=checkbox]) { list-style: none; margin-left: -1.25em; }
li > input[type=checkbox] { margin-right: .45em; vertical-align: -.05em; }
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
