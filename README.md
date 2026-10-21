# DiffEngine, as used in [gnorium.com](https://gnorium.com)

Platform-agnostic diff engine for Swift: unified line diffs of source text and of rendered text.

## Overview

DiffEngine computes line diffs with Swift's `CollectionDifference`, comparing byte for byte and never by Unicode equivalence — a precomposed é and an e with a combining accent are different characters in a diplomatic transcription. Zero dependencies; runs on all Apple platforms, Linux, and Embedded Swift WebAssembly.

## Features

- **Unified line diffs**: every line with its old and new line number, the old lines of a change before the new, and hunks with context
- **Rendered text**: lines of formatted runs, formulas and figures, so a line that only changed its formatting is a changed line
- **Notes on what a reader cannot see**: a changed line paired with the line it replaced says when only spacing, look-alike characters, a figure's region or the kind of break parts them
- **Cross-Platform**: macOS, iOS, watchOS, tvOS, visionOS, Linux, WASM

## Installation

### Swift Package Manager

Add DiffEngine to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/gnorium/diff-engine", branch: "main")
]
```

Then add it to your target dependencies:

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "DiffEngine", package: "diff-engine")
    ]
)
```

## Usage

```swift
import DiffEngine

let lines = DiffEngine.lines(old: pageBefore, new: pageAfter)
for hunk in DiffEngine.hunks(lines, context: 3) {
    for line in hunk {
        // line.kind: .unchanged, .removed or .inserted
        // line.content, line.oldNumber, line.newNumber, line.note
    }
}

// Rendered text: lines of runs that carry their formatting.
let rendered = DiffEngine.lines(
    old: [.init(tokens: [.init(text: "N"), .init(text: "s")])],
    new: [.init(tokens: [.init(text: "N"), .init(text: "s", style: ["sub"])])])
// one removed line, one inserted line
```

### Note

`.spacing`, `.lookalike`, `.region` or `.breakKind`: what parts a changed line from the line it replaced, when a reader could not see it.

## Requirements

- Swift 5.1+ (uses `CollectionDifference`)

## License

Apache License 2.0 - See [LICENSE](LICENSE) for details

## Contributing

Contributions welcome! Please open an issue or submit a pull request.

## Related Packages

- [admin-core](https://github.com/gnorium/admin-core) - Core admin functionalities for web applications
- [artifact-core](https://github.com/gnorium/artifact-core) - IIIF Presentation API v3 types + deep zoom viewer
- [design-tokens](https://github.com/gnorium/design-tokens) - Universal design tokens based on Apple HIG
- [embedded-swift-utilities](https://github.com/gnorium/embedded-swift-utilities) - Utility functions for Embedded Swift environments
- [markdown-utilities](https://github.com/gnorium/markdown-utilities) - Markdown rendering with media attribution support
- [tex-utilities](https://github.com/gnorium/tex-utilities) - TeX formula rendering with locally served KaTeX
- [web-apis](https://github.com/gnorium/web-apis) - Web API implementations for Swift WebAssembly
- [web-builders](https://github.com/gnorium/web-builders) - HTML, CSS, JS, and SVG DSL builders
- [web-components](https://github.com/gnorium/web-components) - Reusable UI components for web applications
- [web-formats](https://github.com/gnorium/web-formats) - Structured data format builders
- [web-security](https://github.com/gnorium/web-security) - Portable security utilities for web applications
- [web-tests](https://github.com/gnorium/web-tests) - Swift browser testing across Chrome and Safari
- [web-types](https://github.com/gnorium/web-types) - Shared web types for web applications
- [xml-utilities](https://github.com/gnorium/xml-utilities) - XML and TEI rendering utilities
