# DiffEngine, as used in [gnorium.com](https://gnorium.com)

Platform-agnostic character-level diff engine for Swift.

## Overview

DiffEngine computes character-level differences between two strings using Swift's `CollectionDifference`. Zero dependencies, works on all Apple platforms, Linux, and WebAssembly.

## Features

- **Character-Level Precision**: Diffs at the character level, not line level
- **Pure Swift**: No Foundation dependency, no platform-specific code
- **Simple API**: One function call, returns typed segments
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

let segments = DiffEngine.diff(old: "hello world", new: "hello earth")

for segment in segments {
    switch segment {
    case .unchanged(let text): print(text)
    case .deleted(let text):   print("-\(text)")
    case .inserted(let text):  print("+\(text)")
    }
}
// "hello " → unchanged
// "wo"     → deleted
// "ea"     → inserted
// "r"      → unchanged
// "ld"     → deleted
// "th"     → inserted
```

### DiffSegment

```swift
public enum DiffSegment: Sendable, Equatable {
    case unchanged(String)  // Present in both
    case inserted(String)   // Added in new
    case deleted(String)    // Removed from old

    var text: String { ... }
}
```

## Requirements

- Swift 5.1+ (uses `CollectionDifference`)

## License

Apache License 2.0 - See [LICENSE](LICENSE) for details

## Contributing

Contributions welcome! Please open an issue or submit a pull request.

## Related Packages

- [admin-core](https://github.com/gnorium/admin-core) - Core admin functionalities for web applications
- [design-tokens](https://github.com/gnorium/design-tokens) - Universal design tokens based on Apple HIG
- [embedded-swift-utilities](https://github.com/gnorium/embedded-swift-utilities) - Utility functions for Embedded Swift environments
- [iiif-core](https://github.com/gnorium/iiif-core) - IIIF Presentation API v3 types + deep zoom viewer
- [markdown-utilities](https://github.com/gnorium/markdown-utilities) - Markdown rendering with media attribution support
- [web-apis](https://github.com/gnorium/web-apis) - Web API implementations for Swift WebAssembly
- [web-builders](https://github.com/gnorium/web-builders) - HTML, CSS, JS, and SVG DSL builders
- [web-components](https://github.com/gnorium/web-components) - Reusable UI components for web applications
- [web-formats](https://github.com/gnorium/web-formats) - Structured data format builders
- [web-security](https://github.com/gnorium/web-security) - Portable security utilities for web applications
- [web-types](https://github.com/gnorium/web-types) - Shared web types and design tokens
