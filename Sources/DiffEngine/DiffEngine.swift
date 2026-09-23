/// Differences between two texts, line by line, as a unified diff has them:
/// the lines both keep, and at each change the old lines then the new. A
/// changed line paired with the line it replaced also says which of its
/// characters changed — found word by word first, then within the words that
/// differ, so a one-letter correction marks one letter and a rewritten phrase
/// marks the phrase, not a scatter of letters that happen to agree.
///
/// Source text is diffed as its lines of characters; rendered text as its
/// lines of runs, so a line that changed only its formatting is a changed
/// line. A changed line paired with the line it replaced is annotated when
/// what parts them is something a reader cannot see: spacing, look-alike
/// characters, a figure's region, the kind of break before it.
///
/// Everything is compared byte for byte, never by Unicode equivalence. A
/// precomposed é and an e followed by a combining accent are different
/// characters in a diplomatic transcription, and a diff that normalised them
/// would hide exactly the change a reader came to see. It also keeps the
/// engine free of the Unicode tables Embedded Swift does not carry, so the
/// same code runs on the server and in the browser.
///
/// Pure Swift, no dependencies: macOS, iOS, Linux and WebAssembly.
public enum DiffEngine {

  // MARK: - Edit script

  /// One step from the old sequence to the new one. Steps come in reading
  /// order, and at every change what goes out comes before what comes in.
  public enum Edit: Sendable {
    case keep(old: Int, new: Int)
    case delete(old: Int)
    case insert(new: Int)
  }

  /// The shortest edit script between two sequences of byte strings.
  public static func edits(old: [[UInt8]], new: [[UInt8]]) -> [Edit] {
    var removed = [Bool](repeating: false, count: old.count)
    var inserted = [Bool](repeating: false, count: new.count)
    for change in new.difference(from: old) {
      switch change {
      case .remove(let offset, _, _): removed[offset] = true
      case .insert(let offset, _, _): inserted[offset] = true
      }
    }
    var script: [Edit] = []
    var i = 0
    var j = 0
    while i < old.count || j < new.count {
      if i < old.count && removed[i] {
        script.append(.delete(old: i))
        i += 1
      } else if j < new.count && inserted[j] {
        script.append(.insert(new: j))
        j += 1
      } else if i < old.count && j < new.count {
        script.append(.keep(old: i, new: j))
        i += 1
        j += 1
      } else {
        break
      }
    }
    return script
  }

  // MARK: - Lines

  /// One line of a unified diff.
  public struct Line<Content: Sendable>: Sendable {
    public enum Kind: Sendable {
      case unchanged, removed, inserted
    }

    public let kind: Kind
    public let content: Content
    /// The line's text, split by what changed against the line it is paired
    /// with: all of it for a line with no pair, none of it for a kept line.
    public let segments: [DiffSegment]
    /// Where it stands in each text, from 1; nil on the side it is not in.
    public let oldNumber: Int?
    public let newNumber: Int?
    /// On a changed line paired with the one it replaced: what parts the two
    /// when a reader could not see it.
    public let note: Note?

    public var isChange: Bool {
      switch kind {
      case .unchanged: return false
      case .removed, .inserted: return true
      }
    }
  }

  /// What parts a changed line from the line it replaced, when it is nothing
  /// a reader could see.
  public enum Note: Sendable {
    /// White space alone: double spaces are diplomatic evidence, and a
    /// rendering collapses them.
    case spacing
    /// Characters that look alike and are not the same: a precomposed letter
    /// and its decomposed spelling, one dash for another.
    case lookalike
    /// The same caption, a different region of the facsimile.
    case region
    /// The same line, after a line break where there was a paragraph break,
    /// or the other way round.
    case breakKind
  }

  /// Two source texts, line by line.
  public static func lines(old: String, new: String) -> [Line<String>] {
    let a = splitLines(old)
    let b = splitLines(new)
    return unified(a, b, keys: (a.map { Array($0.utf8) }, b.map { Array($0.utf8) }), text: { $0 }) { x, y in
      note(x, y)
    }
  }

  /// Two rendered texts, line by line.
  public static func lines(old: [RenderedLine], new: [RenderedLine]) -> [Line<RenderedLine>] {
    unified(old, new, keys: (old.map { $0.key }, new.map { $0.key }), text: { $0.text }) { x, y in
      if Array(x.text.utf8) == Array(y.text.utf8) {
        if x.hasFigure && y.hasFigure { return .region }
        if x.opensBlock != y.opensBlock && Array(x.bodyKey) == Array(y.bodyKey) { return .breakKind }
        return nil
      }
      return note(x.text, y.text)
    }
  }

  /// The lines of both texts in unified order, pairing each change's k-th
  /// removed line with its k-th inserted one for the note and the
  /// characters that changed.
  static func unified<C: Sendable>(
    _ a: [C], _ b: [C], keys: ([[UInt8]], [[UInt8]]), text: (C) -> String, note: (C, C) -> Note?
  ) -> [Line<C>] {
    var out: [Line<C>] = []
    var removed: [Int] = []
    var added: [Int] = []
    func flush() {
      let paired = min(removed.count, added.count)
      var notes = [Note?](repeating: nil, count: max(removed.count, added.count))
      var oldSegments = removed.map { [DiffSegment.changed(text(a[$0]))] }
      var newSegments = added.map { [DiffSegment.changed(text(b[$0]))] }
      for k in 0..<paired {
        notes[k] = note(a[removed[k]], b[added[k]])
        let pair = refine(old: text(a[removed[k]]), new: text(b[added[k]]))
        oldSegments[k] = pair.old
        newSegments[k] = pair.new
      }
      for (k, i) in removed.enumerated() {
        out.append(
          Line(
            kind: .removed, content: a[i], segments: oldSegments[k], oldNumber: i + 1, newNumber: nil,
            note: notes[k]))
      }
      for (k, j) in added.enumerated() {
        out.append(
          Line(
            kind: .inserted, content: b[j], segments: newSegments[k], oldNumber: nil, newNumber: j + 1,
            note: notes[k]))
      }
      removed = []
      added = []
    }
    for edit in edits(old: keys.0, new: keys.1) {
      switch edit {
      case .keep(let i, let j):
        flush()
        out.append(
          Line(
            kind: .unchanged, content: a[i], segments: [.unchanged(text(a[i]))], oldNumber: i + 1,
            newNumber: j + 1, note: nil))
      case .delete(let i):
        if !added.isEmpty { flush() }
        removed.append(i)
      case .insert(let j):
        added.append(j)
      }
    }
    flush()
    return out
  }

  /// The note two differing lines of text earn, if any.
  static func note(_ a: String, _ b: String) -> Note? {
    if withoutSpaces(a) == withoutSpaces(b) { return .spacing }
    if looksAlike(a, b) { return .lookalike }
    return nil
  }

  /// The changed lines with `context` lines either side, in runs: a run ends
  /// where more than twice the context stands unchanged.
  public static func hunks<C: Sendable>(_ lines: [Line<C>], context: Int) -> [[Line<C>]] {
    var shown = [Bool](repeating: false, count: lines.count)
    for (index, line) in lines.enumerated() where line.isChange {
      let from = max(0, index - context)
      let to = min(lines.count - 1, index + context)
      for k in from...to { shown[k] = true }
    }
    var out: [[Line<C>]] = []
    var current: [Line<C>] = []
    for (index, line) in lines.enumerated() {
      if shown[index] {
        current.append(line)
      } else if !current.isEmpty {
        out.append(current)
        current = []
      }
    }
    if !current.isEmpty { out.append(current) }
    return out
  }

  static func splitLines(_ text: String) -> [String] {
    var out: [String] = []
    var current: [UInt8] = []
    for byte in text.utf8 {
      if byte == 0x0A {
        out.append(String(decoding: current, as: UTF8.self))
        current = []
      } else {
        current.append(byte)
      }
    }
    out.append(String(decoding: current, as: UTF8.self))
    return out
  }

  // MARK: - Within a line

  /// Two lines' texts, each split into what the other kept and what changed.
  ///
  /// Words first — words, runs of white space, and each punctuation mark on
  /// its own — so a rewritten phrase is one change; then, within a change
  /// that kept at least half of its shorter side's characters, the
  /// characters, so a corrected letter is one letter. A space kept alone
  /// between two changes is folded into them.
  public static func refine(old: String, new: String) -> (old: [DiffSegment], new: [DiffSegment]) {
    let a = tokens(old)
    let b = tokens(new)
    var before: [DiffSegment] = []
    var after: [DiffSegment] = []
    let script = edits(old: a.map { Array($0.utf8) }, new: b.map { Array($0.utf8) })
    for group in groups(script, isSpace: { isSpace(a[$0]) }) {
      switch group {
      case .keep(let i, _):
        append(.unchanged(a[i]), to: &before)
        append(.unchanged(a[i]), to: &after)
      case .change(let removed, let added):
        let letters = characters(old: join(removed.map { a[$0] }), new: join(added.map { b[$0] }))
        for segment in letters.old { append(segment, to: &before) }
        for segment in letters.new { append(segment, to: &after) }
      }
    }
    return (before, after)
  }

  /// Two outline numbers — 1.2, 2.3.1 — each split into the segments the
  /// other kept and the ones that changed. A number is read by position, not
  /// aligned: its first segment is the first level, whatever the other
  /// number's first segment is, so 1.2 → 2.3 changes both levels rather than
  /// keeping a "2" that moved from one level to the other. A segment is kept
  /// or changed whole, the point before it with it; segments one number has
  /// past the end of the other are changed.
  public static func outline(old: String, new: String) -> (old: [DiffSegment], new: [DiffSegment]) {
    let a = segments(old)
    let b = segments(new)
    func marked(_ own: [[UInt8]], against other: [[UInt8]]) -> [DiffSegment] {
      var out: [DiffSegment] = []
      for (index, segment) in own.enumerated() {
        let text = String(decoding: (index == 0 ? [] : [0x2E]) + segment, as: UTF8.self)
        let kept = index < other.count && other[index] == segment
        append(kept ? .unchanged(text) : .changed(text), to: &out)
      }
      return out
    }
    return (marked(a, against: b), marked(b, against: a))
  }

  /// A number's segments, between its points.
  static func segments(_ number: String) -> [[UInt8]] {
    guard !number.isEmpty else { return [] }
    return number.utf8.split(separator: 0x2E, omittingEmptySubsequences: false).map(Array.init)
  }

  /// One change, character by character — or whole, when so little of it
  /// agrees that marking the agreement would only scatter the change.
  static func characters(old: String, new: String) -> (old: [DiffSegment], new: [DiffSegment]) {
    let a = old.unicodeScalars.map { Array($0.utf8) }
    let b = new.unicodeScalars.map { Array($0.utf8) }
    guard !a.isEmpty, !b.isEmpty else {
      return (a.isEmpty ? [] : [.changed(old)], b.isEmpty ? [] : [.changed(new)])
    }
    let script = edits(old: a, new: b)
    var kept = 0
    for edit in script {
      if case .keep = edit { kept += 1 }
    }
    guard kept * 2 >= min(a.count, b.count) else { return ([.changed(old)], [.changed(new)]) }
    var before: [DiffSegment] = []
    var after: [DiffSegment] = []
    for edit in script {
      switch edit {
      case .keep(let i, _):
        append(.unchanged(String(decoding: a[i], as: UTF8.self)), to: &before)
        append(.unchanged(String(decoding: a[i], as: UTF8.self)), to: &after)
      case .delete(let i):
        append(.changed(String(decoding: a[i], as: UTF8.self)), to: &before)
      case .insert(let j):
        append(.changed(String(decoding: b[j], as: UTF8.self)), to: &after)
      }
    }
    return (before, after)
  }

  /// Words, runs of white space, and each punctuation mark on its own — so
  /// a change of one tag's attribute is a change of that value, not of the
  /// whole tag.
  public static func tokens(_ text: String) -> [String] {
    var out: [String] = []
    var current: [UInt8] = []
    var currentClass = CharacterClass.word
    for byte in text.utf8 {
      let kind = CharacterClass(byte)
      if case .punctuation = kind {
        if !current.isEmpty { out.append(String(decoding: current, as: UTF8.self)) }
        current = []
        out.append(String(decoding: [byte], as: UTF8.self))
        continue
      }
      if !current.isEmpty && !kind.continues(currentClass) {
        out.append(String(decoding: current, as: UTF8.self))
        current = []
      }
      current.append(byte)
      currentClass = kind
    }
    if !current.isEmpty { out.append(String(decoding: current, as: UTF8.self)) }
    return out
  }

  enum CharacterClass {
    case space, word, punctuation

    init(_ byte: UInt8) {
      switch byte {
      case 0x20, 0x09, 0x0A, 0x0D: self = .space
      // Letters, digits and every byte of a multi-byte character.
      case 0x30...0x39, 0x41...0x5A, 0x61...0x7A, 0x5F, 0x80...0xFF: self = .word
      default: self = .punctuation
      }
    }

    func continues(_ other: CharacterClass) -> Bool {
      switch (self, other) {
      case (.space, .space), (.word, .word): return true
      default: return false
      }
    }
  }

  /// Whether a text is white space alone.
  public static func isSpace(_ text: String) -> Bool {
    for byte in text.utf8 {
      guard case .space = CharacterClass(byte) else { return false }
    }
    return true
  }

  /// A run of the edit script: something kept, or one change — what it took
  /// out and what it put in, by index.
  enum Group {
    case keep(old: Int, new: Int)
    case change(removed: [Int], added: [Int])
  }

  static func groups(_ script: [Edit], isSpace: (Int) -> Bool) -> [Group] {
    var out: [Group] = []
    for edit in script {
      switch edit {
      case .keep(let i, let j):
        out.append(.keep(old: i, new: j))
      case .delete(let i):
        if case .change(let removed, let added)? = out.last {
          out[out.count - 1] = .change(removed: removed + [i], added: added)
        } else {
          out.append(.change(removed: [i], added: []))
        }
      case .insert(let j):
        if case .change(let removed, let added)? = out.last {
          out[out.count - 1] = .change(removed: removed, added: added + [j])
        } else {
          out.append(.change(removed: [], added: [j]))
        }
      }
    }
    var folded: [Group] = []
    var index = 0
    while index < out.count {
      if index + 2 < out.count,
        case .change(let r1, let a1) = out[index],
        case .keep(let i, let j) = out[index + 1], isSpace(i),
        case .change(let r2, let a2) = out[index + 2]
      {
        // Fold, and look again: the folded change may meet another space.
        out[index + 2] = .change(removed: r1 + [i] + r2, added: a1 + [j] + a2)
        index += 2
        continue
      }
      folded.append(out[index])
      index += 1
    }
    return folded
  }

  static func join(_ parts: [String]) -> String {
    var out = ""
    for part in parts { out += part }
    return out
  }

  /// Appends a segment, joining it to the last one when they share a fate.
  /// An empty segment is dropped.
  static func append(_ segment: DiffSegment, to segments: inout [DiffSegment]) {
    let text = segment.text
    guard !text.utf8.isEmpty else { return }
    if let last = segments.last {
      switch (last, segment) {
      case (.unchanged(let a), .unchanged):
        segments[segments.count - 1] = .unchanged(a + text)
        return
      case (.changed(let a), .changed):
        segments[segments.count - 1] = .changed(a + text)
        return
      default: break
      }
    }
    segments.append(segment)
  }

  // MARK: - Rendered text

  /// A stretch of one rendered line set one way, or something that stands
  /// whole in it.
  public struct Token: Sendable {
    public enum Kind: Sendable {
      /// Words and the spaces between them, set as `style` says.
      case text
      /// Atomic: a formula is compared and shown whole.
      case formula
      /// A drawn region; its text is its caption, its style its region.
      case figure
    }

    public let kind: Kind
    public let text: String
    /// How it is set — "italic", "sub" — in a stable order.
    public let style: [String]

    public init(kind: Kind = .text, text: String, style: [String] = []) {
      self.kind = kind
      self.text = text
      self.style = style
    }

    var key: [UInt8] {
      var bytes: [UInt8]
      switch kind {
      case .text: bytes = [1]
      case .formula: bytes = [2]
      case .figure: bytes = [3]
      }
      for (index, name) in style.enumerated() {
        if index > 0 { bytes.append(0x1E) }
        bytes.append(contentsOf: Array(name.utf8))
      }
      bytes.append(0x1F)
      bytes.append(contentsOf: Array(text.utf8))
      bytes.append(0x1D)
      return bytes
    }
  }

  /// One line of rendered text: its runs, whether it opens a block — a
  /// paragraph, a verse line, a heading — rather than following a line break,
  /// and the part it plays: "heading", "stage", "forme-header", "page".
  public struct RenderedLine: Sendable {
    public let tokens: [Token]
    public let opensBlock: Bool
    public let role: String

    public init(tokens: [Token], opensBlock: Bool = true, role: String = "") {
      self.tokens = tokens
      self.opensBlock = opensBlock
      self.role = role
    }

    /// What it reads, without its formatting.
    public var text: String {
      var out = ""
      for token in tokens { out += token.text }
      return out
    }

    var hasFigure: Bool {
      tokens.contains { token in
        if case .figure = token.kind { return true }
        return false
      }
    }

    var bodyKey: [UInt8] {
      var bytes = Array(role.utf8)
      bytes.append(0x1C)
      for token in tokens { bytes.append(contentsOf: token.key) }
      return bytes
    }

    var key: [UInt8] { [opensBlock ? 1 : 0] + bodyKey }
  }

  // MARK: - Characters

  /// Whether two different texts would be read as the same: canonically
  /// equivalent spellings, or dashes, quotes and spaces of one family.
  public static func looksAlike(_ a: String, _ b: String) -> Bool {
    guard Array(a.utf8) != Array(b.utf8) else { return false }
    #if SERVER
      // Swift compares strings by canonical equivalence: a precomposed letter
      // equals its decomposed spelling here and nowhere else in this file.
      if a == b { return true }
    #endif
    return skeleton(a) == skeleton(b)
  }

  static func skeleton(_ text: String) -> [UInt32] {
    text.unicodeScalars.map { scalar in
      switch scalar.value {
      case 0x2D, 0x2010...0x2015, 0x2212, 0xFE58, 0xFE63, 0xFF0D: return 0x2D
      case 0x27, 0x2018, 0x2019, 0x201B, 0x02BC, 0x2032: return 0x27
      case 0x22, 0x201C, 0x201D, 0x201F, 0x2033: return 0x22
      case 0x20, 0xA0, 0x2000...0x200A, 0x202F, 0x205F, 0x3000: return 0x20
      default: return scalar.value
      }
    }
  }

  static func withoutSpaces(_ text: String) -> [UInt8] {
    text.utf8.filter { byte in
      switch byte {
      case 0x20, 0x09, 0x0A, 0x0D: return false
      default: return true
      }
    }
  }
}
