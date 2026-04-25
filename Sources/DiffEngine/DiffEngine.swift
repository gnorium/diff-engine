#if CLIENT
  import EmbeddedSwiftUtilities
#endif

/// Two-pass diff engine using Swift's `CollectionDifference`.
/// Pass 1: line-level diff to identify changed regions.
/// Pass 2: word-level diff within changed line pairs.
///
/// Output uses two levels of highlighting:
/// - Line-level: `deletedContext`/`insertedContext` for subtle background on entire changed lines
/// - Word-level: `deleted`/`inserted` for strong highlight on specific changed words
///
/// Pure Swift, zero dependencies (except EmbeddedSwiftUtilities for WASM) — works on all Apple platforms, Linux, and WASM.
public enum DiffEngine {

  /// Computes a diff between two strings.
  public static func diff(old: String, new: String) -> [DiffSegment] {
    let oldLines: [String]
    let newLines: [String]

    #if SERVER
      if old == new { return old.isEmpty ? [] : [.unchanged(old)] }
      if old.isEmpty { return [.inserted(new)] }
      if new.isEmpty { return [.deleted(old)] }

      // Pass 1: line-level diff
      oldLines = old.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
      newLines = new.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    #endif
    #if CLIENT
      if stringEquals(old, new) { return stringIsEmpty(old) ? [] : [.unchanged(old)] }
      if stringIsEmpty(old) { return [.inserted(new)] }
      if stringIsEmpty(new) { return [.deleted(old)] }

      // Pass 1: line-level diff
      oldLines = stringSplit(old, separator: "\n")
      newLines = stringSplit(new, separator: "\n")
    #endif

    let lineDiff = newLines.difference(from: oldLines)

    var removedLineIndices = Set<Int>()
    var insertedLineIndices = Set<Int>()

    for change in lineDiff {
      switch change {
      case .remove(let offset, _, _):
        removedLineIndices.insert(offset)
      case .insert(let offset, _, _):
        insertedLineIndices.insert(offset)
      }
    }

    var segments: [DiffSegment] = []
    var oi = 0
    var ni = 0

    while oi < oldLines.count || ni < newLines.count {
      var removedLines: [String] = []
      while oi < oldLines.count && removedLineIndices.contains(oi) {
        removedLines.append(oldLines[oi])
        oi += 1
      }

      var insertedLines: [String] = []
      while ni < newLines.count && insertedLineIndices.contains(ni) {
        insertedLines.append(newLines[ni])
        ni += 1
      }

      processHunk(removed: removedLines, inserted: insertedLines, into: &segments)

      if oi < oldLines.count && ni < newLines.count {
        if !segments.isEmpty || oi > 0 {
          appendSegment(.unchanged("\n"), to: &segments)
        }
        appendSegment(.unchanged(newLines[ni]), to: &segments)
        oi += 1
        ni += 1
      }
    }

    return segments
  }

  // MARK: - Hunk Processing

  private static func processHunk(
    removed: [String], inserted: [String], into segments: inout [DiffSegment]
  ) {
    let pairedCount = min(removed.count, inserted.count)

    // Paired lines: word-level diff, old line then new line
    for i in 0..<pairedCount {
      if !(i == 0 && segments.isEmpty) {
        appendSegment(.unchanged("\n"), to: &segments)
      }
      diffLineByWords(old: removed[i], new: inserted[i], into: &segments)
    }

    // Unpaired removed lines: entire line is deletedContext (fully removed)
    for i in pairedCount..<removed.count {
      if !segments.isEmpty { appendSegment(.unchanged("\n"), to: &segments) }
      appendSegment(.deleted(removed[i]), to: &segments)
    }

    // Unpaired inserted lines: entire line is insertedContext (fully added)
    for i in pairedCount..<inserted.count {
      if !segments.isEmpty { appendSegment(.unchanged("\n"), to: &segments) }
      appendSegment(.inserted(inserted[i]), to: &segments)
    }
  }

  // MARK: - Word-level diff within a line pair
  //
  // For each changed line pair, emit two visual lines:
  //   1. OLD line: unchanged words as deletedContext (subtle red), changed words as deleted (strong red)
  //   2. NEW line: unchanged words as insertedContext (subtle green), changed words as inserted (strong green)

  private static func diffLineByWords(old: String, new: String, into segments: inout [DiffSegment])
  {
    #if SERVER
      if old == new {
        appendSegment(.unchanged(old), to: &segments)
        return
      }
      if old.isEmpty {
        appendSegment(.inserted(new), to: &segments)
        return
      }
      if new.isEmpty {
        appendSegment(.deleted(old), to: &segments)
        return
      }
    #endif
    #if CLIENT
      if stringEquals(old, new) {
        appendSegment(.unchanged(old), to: &segments)
        return
      }
      if stringIsEmpty(old) {
        appendSegment(.inserted(new), to: &segments)
        return
      }
      if stringIsEmpty(new) {
        appendSegment(.deleted(old), to: &segments)
        return
      }
    #endif

    let oldTokens = tokenize(old)
    let newTokens = tokenize(new)

    let wordDiff = newTokens.difference(from: oldTokens)

    var removedWordIndices = Set<Int>()
    var insertedWordIndices = Set<Int>()

    for change in wordDiff {
      switch change {
      case .remove(let offset, _, _):
        removedWordIndices.insert(offset)
      case .insert(let offset, _, _):
        insertedWordIndices.insert(offset)
      }
    }

    // OLD line: unchanged words → deletedContext, removed words → deleted
    for i in 0..<oldTokens.count {
      if removedWordIndices.contains(i) {
        appendSegment(.deleted(oldTokens[i]), to: &segments)
      } else {
        appendSegment(.deletedContext(oldTokens[i]), to: &segments)
      }
    }

    appendSegment(.unchanged("\n"), to: &segments)

    // NEW line: unchanged words → insertedContext, inserted words → inserted
    for i in 0..<newTokens.count {
      if insertedWordIndices.contains(i) {
        appendSegment(.inserted(newTokens[i]), to: &segments)
      } else {
        appendSegment(.insertedContext(newTokens[i]), to: &segments)
      }
    }
  }

  // MARK: - Tokenizer

  /// Splits text into alternating word and whitespace tokens.
  private static func tokenize(_ text: String) -> [String] {
    #if SERVER
      var tokens: [String] = []
      var current: [Character] = []
      var inWhitespace = false

      for char in text {
        let charIsWhitespace = char.isWhitespace
        if current.isEmpty {
          inWhitespace = charIsWhitespace
          current.append(char)
        } else if charIsWhitespace == inWhitespace {
          current.append(char)
        } else {
          tokens.append(String(current))
          current = [char]
          inWhitespace = charIsWhitespace
        }
      }

      if !current.isEmpty {
        tokens.append(String(current))
      }

      return tokens
    #endif
    #if CLIENT
      var tokens: [String] = []
      var current: [UInt8] = []
      var inWhitespace = false

      let utf8 = Array(text.utf8)
      for byte in utf8 {
        let byteIsWhitespace = byte == 32 || byte == 9 || byte == 10 || byte == 13
        if current.isEmpty {
          inWhitespace = byteIsWhitespace
          current.append(byte)
        } else if byteIsWhitespace == inWhitespace {
          current.append(byte)
        } else {
          tokens.append(String(decoding: current, as: UTF8.self))
          current = [byte]
          inWhitespace = byteIsWhitespace
        }
      }

      if !current.isEmpty {
        tokens.append(String(decoding: current, as: UTF8.self))
      }

      return tokens
    #endif
  }

  // MARK: - Segment Helpers

  /// Appends a segment, coalescing with the last segment if it's the same kind.
  private static func appendSegment(_ segment: DiffSegment, to segments: inout [DiffSegment]) {
    let text = segment.text
    guard !text.isEmpty else { return }

    if let last = segments.last {
      switch (last, segment) {
      case (.unchanged(let a), .unchanged):
        segments[segments.count - 1] = .unchanged(a + text)
        return
      case (.deleted(let a), .deleted):
        segments[segments.count - 1] = .deleted(a + text)
        return
      case (.inserted(let a), .inserted):
        segments[segments.count - 1] = .inserted(a + text)
        return
      case (.deletedContext(let a), .deletedContext):
        segments[segments.count - 1] = .deletedContext(a + text)
        return
      case (.insertedContext(let a), .insertedContext):
        segments[segments.count - 1] = .insertedContext(a + text)
        return
      default: break
      }
    }

    segments.append(segment)
  }
}
