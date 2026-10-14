/// Differences between two texts, line by line, as a unified diff has them:
/// the lines both keep, and at each change the old lines then the new. The
/// standard algorithm, as jsdiff and git's word diff have it, with no
/// thresholds (user, 2026-10-11): Myers on lines; within a change, each
/// removed line paired with the added one most like it, in order (`pairs`),
/// the rest k-th with k-th; within a pair, Myers on its
/// tokens (words, white space runs, each punctuation mark), the tokens that
/// differ marked whole, and diff-match-patch's semantic cleanup folding the
/// short equalities between changes into them.
///
/// Source text is diffed as its lines of characters; rendered text as its
/// lines of runs, so a line that changed only its formatting is a changed
/// line. A changed line paired with the line it replaced is annotated when
/// what parts them is something a reader cannot see: spacing, look-alike
/// characters, a figure's region, the kind of break before it.
///
/// Everything is compared byte for byte, never by Unicode equivalence. A
/// precomposed é and an e followed by a combining accent are different
/// characters in a diplomatic transcription, and a diff that normalized them
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
    /// Whether the line break ending it changed: put in (an inserted line)
    /// or taken out (a removed one), where a change re-broke its lines.
    public var breakChanged = false

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

  /// Two source texts, line by line. `markup` for XML (TEI): within a
  /// line its tags are tokens whole, and a change that can slide is put
  /// where it is balanced XML (`refine`).
  public static func lines(old: String, new: String, markup: Bool = false) -> [Line<String>] {
    let a = splitLines(old)
    let b = splitLines(new)
    return unified(
      a, b, keys: (a.map { Array($0.utf8) }, b.map { Array($0.utf8) }), text: { $0 }, markup: markup
    ) { x, y in
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

  /// The lines of both texts in unified order, pairing each change's
  /// removed lines with its inserted ones (`pairs`), for the note and the
  /// tokens that changed; a line past the other side's count stands whole.
  static func unified<C: Sendable>(
    _ a: [C], _ b: [C], keys: ([[UInt8]], [[UInt8]]), text: (C) -> String, markup: Bool = false,
    note: (C, C) -> Note?
  ) -> [Line<C>] {
    var out: [Line<C>] = []
    var removed: [Int] = []
    var added: [Int] = []
    func flush() {
      if let block = reflowed() {
        out += block
        removed = []
        added = []
        return
      }
      var oldNotes = [Note?](repeating: nil, count: removed.count)
      var newNotes = [Note?](repeating: nil, count: added.count)
      var oldSegments = removed.map { [DiffSegment.changed(text(a[$0]))] }
      var newSegments = added.map { [DiffSegment.changed(text(b[$0]))] }
      for (k, l) in pairs(removed.map { text(a[$0]) }, added.map { text(b[$0]) }, markup: markup) {
        let n = note(a[removed[k]], b[added[l]])
        oldNotes[k] = n
        newNotes[l] = n
        let pair = refine(old: text(a[removed[k]]), new: text(b[added[l]]), markup: markup)
        oldSegments[k] = pair.old
        newSegments[l] = pair.new
      }
      for (k, i) in removed.enumerated() {
        out.append(
          Line(
            kind: .removed, content: a[i], segments: oldSegments[k], oldNumber: i + 1, newNumber: nil,
            note: oldNotes[k]))
      }
      for (k, j) in added.enumerated() {
        out.append(
          Line(
            kind: .inserted, content: b[j], segments: newSegments[k], oldNumber: nil, newNumber: j + 1,
            note: newNotes[k]))
      }
      removed = []
      added = []
    }
    /// A change that re-broke its lines—one line now several, or the same
    /// text indented anew, its text alike but for white space—compared as
    /// one block, so only the white space and line breaks it put in or took
    /// out are marked. Nil for any other change, whose lines are paired one
    /// by one.
    func reflowed() -> [Line<C>]? {
      guard !removed.isEmpty, !added.isEmpty else { return nil }
      let before = join(removed.map { text(a[$0]) }, separator: "\n")
      let after = join(added.map { text(b[$0]) }, separator: "\n")
      // The same text, changed only in how it is set (its style, a
      // figure's region, the kind of break): the pairs say how.
      guard Array(before.utf8) != Array(after.utf8) else { return nil }
      guard withoutSpaces(before) == withoutSpaces(after) else { return nil }
      let pair = refine(old: before, new: after, markup: markup)
      let oldLines = Self.split(pair.old)
      let newLines = Self.split(pair.new)
      guard oldLines.count == removed.count, newLines.count == added.count else { return nil }
      var block: [Line<C>] = []
      for (k, i) in removed.enumerated() {
        var line = Line(
          kind: .removed, content: a[i], segments: oldLines[k].segments, oldNumber: i + 1, newNumber: nil,
          note: .spacing)
        line.breakChanged = oldLines[k].breakChanged
        block.append(line)
      }
      for (k, j) in added.enumerated() {
        var line = Line(
          kind: .inserted, content: b[j], segments: newLines[k].segments, oldNumber: nil, newNumber: j + 1,
          note: .spacing)
        line.breakChanged = newLines[k].breakChanged
        block.append(line)
      }
      return block
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

  /// Which removed line of a change is paired with which added one, in
  /// order (user, 2026-10-14): each line with the one most like it, as
  /// GitHub's and Xcode's word diffs pair them, so a line put in before a
  /// changed one never takes its partner. The order-keeping alignment of
  /// the two runs that shares the most tokens (a line's likeness to another
  /// is the Dice coefficient of their tokens, white space aside); the lines
  /// it leaves between two pairs then paired k-th with k-th, as before, so
  /// two lines sharing no token—one dash for another—still pair. A change
  /// too large to align (over `alignable` pairs of lines) is paired k-th
  /// with k-th throughout.
  static func pairs(_ removed: [String], _ added: [String], markup: Bool) -> [(Int, Int)] {
    guard !removed.isEmpty, !added.isEmpty else { return [] }
    var anchors: [(Int, Int)] = []
    if removed.count * added.count <= alignable, removed.count > 1 || added.count > 1 {
      let oldBags = removed.map { bag($0, markup: markup) }
      let newBags = added.map { bag($0, markup: markup) }
      let width = added.count + 1
      var score = [Double](repeating: 0, count: (removed.count + 1) * width)
      var like = [Double](repeating: 0, count: removed.count * added.count)
      for i in 0..<removed.count {
        for j in 0..<added.count {
          like[i * added.count + j] = likeness(oldBags[i], newBags[j])
        }
      }
      for i in 1...removed.count {
        for j in 1...added.count {
          var best = max(score[(i - 1) * width + j], score[i * width + j - 1])
          let together = like[(i - 1) * added.count + j - 1]
          if together > 0 { best = max(best, score[(i - 1) * width + j - 1] + together) }
          score[i * width + j] = best
        }
      }
      var i = removed.count
      var j = added.count
      while i > 0 && j > 0 {
        let together = like[(i - 1) * added.count + j - 1]
        if together > 0 && score[i * width + j] == score[(i - 1) * width + j - 1] + together {
          anchors.append((i - 1, j - 1))
          i -= 1
          j -= 1
        } else if score[i * width + j] == score[(i - 1) * width + j] {
          i -= 1
        } else {
          j -= 1
        }
      }
      anchors.reverse()
    }
    // Between the anchors (and before the first, after the last), the
    // lines left paired in order.
    var out: [(Int, Int)] = []
    var from = (0, 0)
    for anchor in anchors + [(removed.count, added.count)] {
      let count = min(anchor.0 - from.0, anchor.1 - from.1)
      for k in 0..<max(0, count) { out.append((from.0 + k, from.1 + k)) }
      if anchor.0 < removed.count { out.append(anchor) }
      from = (anchor.0 + 1, anchor.1 + 1)
    }
    return out
  }

  /// The most pairs of lines a change is aligned over (`pairs`): a
  /// thousand lines out and a thousand in is a million likenesses.
  static let alignable = 250_000

  /// A line's tokens, white space aside, each as its bytes' FNV-1a hash,
  /// sorted: what `likeness` counts in common.
  static func bag(_ text: String, markup: Bool) -> [UInt64] {
    var out: [UInt64] = []
    for token in markup ? markupTokens(text) : tokens(text) where !isSpace(token) {
      var hash: UInt64 = 0xcbf2_9ce4_8422_2325
      for byte in token.utf8 {
        hash ^= UInt64(byte)
        hash = hash &* 0x0000_0100_0000_01B3
      }
      out.append(hash)
    }
    out.sort()
    return out
  }

  /// The Dice coefficient of two lines' tokens: twice the tokens they
  /// share over how many both have, 0 to 1.
  static func likeness(_ a: [UInt64], _ b: [UInt64]) -> Double {
    guard !a.isEmpty || !b.isEmpty else { return 0 }
    var i = 0
    var j = 0
    var shared = 0
    while i < a.count && j < b.count {
      if a[i] == b[j] {
        shared += 1
        i += 1
        j += 1
      } else if a[i] < b[j] {
        i += 1
      } else {
        j += 1
      }
    }
    return Double(2 * shared) / Double(a.count + b.count)
  }

  /// A block's segments, split back into its lines at its line feeds: each
  /// line's own, and whether the break ending it changed.
  static func split(_ segments: [DiffSegment]) -> [(segments: [DiffSegment], breakChanged: Bool)] {
    var out: [(segments: [DiffSegment], breakChanged: Bool)] = []
    var current: [DiffSegment] = []
    for segment in segments {
      let changed: Bool
      switch segment {
      case .unchanged: changed = false
      case .changed: changed = true
      }
      let parts = splitLines(segment.text)
      for (index, part) in parts.enumerated() {
        if !part.utf8.isEmpty { append(changed ? .changed(part) : .unchanged(part), to: &current) }
        if index < parts.count - 1 {
          out.append((current, changed))
          current = []
        }
      }
    }
    out.append((current, false))
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
    // No text is no lines, not one empty line: a page that had no markup
    // diffs as all added, never with a removed blank first (user, 2026-10-10).
    if text.utf8.isEmpty { return [] }
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
  /// Myers on tokens—words, runs of white space, and each punctuation mark
  /// on its own—each token that differs marked whole, as git's word diff and
  /// GitHub's word highlighting mark it: never part of a word (user,
  /// 2026-10-11), so a corrected letter marks its word. Then the semantic
  /// cleanup of Neil Fraser's diff-match-patch (`cleanupSemantic`): an
  /// equality no longer than the edits on both sides of it is folded into
  /// them, so the spaces and commas kept between changed words do not cut a
  /// changed run into pieces ("pink, red, orange" against "red, orange,
  /// pink" reads as one change, not a word here and a comma there).
  ///
  /// `markup` for XML (TEI): a tag is one token whole (`markupTokens`), and
  /// an insertion or a deletion that can slide among equivalent places is
  /// put at the earliest where what it marks is balanced XML, every tag it
  /// opens closed inside it and every tag it closes opened inside it
  /// (`balanced`); where no place is, it stays where it was (user,
  /// 2026-10-12). A rule, never a guess: inserting `<w>b</w> ` between
  /// `<w>a</w> ` and `<w>c</w>` marks ` <w>b</w>`, never `b</w> <w>`.
  public static func refine(old: String, new: String, markup: Bool = false) -> (
    old: [DiffSegment], new: [DiffSegment]
  ) {
    let a = markup ? markupTokens(old) : tokens(old)
    let b = markup ? markupTokens(new) : tokens(new)
    var diffs: [(Operation, String)] = []
    for edit in edits(old: a.map { Array($0.utf8) }, new: b.map { Array($0.utf8) }) {
      switch edit {
      case .keep(let i, _): diffs.append((.equal, a[i]))
      case .delete(let i): diffs.append((.delete, a[i]))
      case .insert(let j): diffs.append((.insert, b[j]))
      }
    }
    var before: [DiffSegment] = []
    var after: [DiffSegment] = []
    // Markup: each edit put where it is balanced before the cleanup weighs
    // the equalities between edits, and again after it folds some in.
    let cleaned =
      markup
      ? balancedSlides(cleanupSemantic(balancedSlides(merged(diffs)))) : cleanupSemantic(merged(diffs))
    for (operation, text) in cleaned {
      switch operation {
      case .equal:
        append(.unchanged(text), to: &before)
        append(.unchanged(text), to: &after)
      case .delete:
        append(.changed(text), to: &before)
      case .insert:
        append(.changed(text), to: &after)
      }
    }
    return (before, after)
  }

  /// One step of a diff as diff-match-patch writes it.
  enum Operation: Equatable {
    case equal, delete, insert
  }

  /// The length diff-match-patch measures a text by: its characters (here,
  /// its Unicode scalars).
  static func length(_ text: String) -> Int {
    var count = 0
    for _ in text.unicodeScalars { count += 1 }
    return count
  }

  /// diff-match-patch's `cleanupSemantic`, its first pass (Neil Fraser,
  /// https://github.com/google/diff-match-patch, `diff_cleanupSemantic`):
  /// walk the equalities; where one is no longer than the larger of the
  /// edits before it and no longer than the larger of the edits after it,
  /// split it into a deletion and an insertion of its text, step back to
  /// the equality before, and go on; then merge (`merged`). Its later
  /// passes shift and split edits by characters, which whole tokens never
  /// need.
  static func cleanupSemantic(_ input: [(Operation, String)]) -> [(Operation, String)] {
    var diffs = input
    var changes = false
    var equalities: [Int] = []
    var lastEquality: String? = nil
    var pointer = 0
    var insertions1 = 0, deletions1 = 0, insertions2 = 0, deletions2 = 0
    while pointer < diffs.count {
      if diffs[pointer].0 == .equal {
        equalities.append(pointer)
        insertions1 = insertions2
        deletions1 = deletions2
        insertions2 = 0
        deletions2 = 0
        lastEquality = diffs[pointer].1
      } else {
        if diffs[pointer].0 == .insert { insertions2 += length(diffs[pointer].1) } else {
          deletions2 += length(diffs[pointer].1)
        }
        if let equality = lastEquality, length(equality) <= max(insertions1, deletions1),
          length(equality) <= max(insertions2, deletions2), let at = equalities.last
        {
          diffs.insert((.delete, equality), at: at)
          diffs[at + 1] = (.insert, equality)
          equalities.removeLast()
          if !equalities.isEmpty { equalities.removeLast() }
          pointer = equalities.last ?? -1
          insertions1 = 0
          deletions1 = 0
          insertions2 = 0
          deletions2 = 0
          lastEquality = nil
          changes = true
        }
      }
      pointer += 1
    }
    return changes ? merged(diffs) : diffs
  }

  /// diff-match-patch's `cleanupMerge`, for whole tokens: between two
  /// equalities, everything taken out as one deletion and then everything
  /// put in as one insertion; neighboring equalities joined.
  static func merged(_ diffs: [(Operation, String)]) -> [(Operation, String)] {
    var out: [(Operation, String)] = []
    var deleted = ""
    var inserted = ""
    func flush() {
      if !deleted.isEmpty { out.append((.delete, deleted)) }
      if !inserted.isEmpty { out.append((.insert, inserted)) }
      deleted = ""
      inserted = ""
    }
    for (operation, text) in diffs {
      switch operation {
      case .delete: deleted += text
      case .insert: inserted += text
      case .equal:
        flush()
        if let last = out.last, last.0 == .equal {
          out[out.count - 1] = (.equal, last.1 + text)
        } else if !text.isEmpty {
          out.append((.equal, text))
        }
      }
    }
    flush()
    return out
  }

  /// Two outline numbers—1.2, 2.3.1—each split into the segments the
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

  /// Words, runs of white space, and each punctuation mark on its own—so
  /// a change of one tag's attribute is a change of that value, not of the
  /// whole tag, and a dash closed up ("a — b" → "a—b") is a change of the
  /// spaces around it. Read by Unicode scalar (`CharacterClass`).
  public static func tokens(_ text: String) -> [String] {
    var out: [String] = []
    var current = ""
    var currentClass = CharacterClass.word
    for scalar in text.unicodeScalars {
      let kind = CharacterClass(scalar.value)
      if case .punctuation = kind {
        if !current.isEmpty { out.append(current) }
        current = ""
        out.append(String(scalar))
        continue
      }
      if !current.isEmpty && !kind.continues(currentClass) {
        out.append(current)
        current = ""
      }
      current.unicodeScalars.append(scalar)
      currentClass = kind
    }
    if !current.isEmpty { out.append(current) }
    return out
  }

  /// XML's tokens: each tag, comment or processing instruction whole, from
  /// its `<` to its `>`; between them, the text's own tokens (`tokens`).
  public static func markupTokens(_ text: String) -> [String] {
    var out: [String] = []
    var run = ""
    var tag = ""
    var inTag = false
    for scalar in text.unicodeScalars {
      if inTag {
        tag.unicodeScalars.append(scalar)
        if scalar.value == 0x3E {
          out.append(tag)
          tag = ""
          inTag = false
        }
      } else if scalar.value == 0x3C {
        if !run.isEmpty { out += tokens(run) }
        run = ""
        tag.unicodeScalars.append(scalar)
        inTag = true
      } else {
        run.unicodeScalars.append(scalar)
      }
    }
    if !run.isEmpty { out += tokens(run) }
    // A `<` never closed is text.
    if !tag.isEmpty { out += tokens(tag) }
    return out
  }

  /// A tag token's kind and name: a start tag, an end tag, or neither (a
  /// self-closing tag, a comment, a processing instruction, text).
  enum TagKind {
    case start([UInt8]), end([UInt8]), other
  }

  static func tagKind(_ token: String) -> TagKind {
    let bytes = Array(token.utf8)
    guard bytes.count >= 3, bytes[0] == 0x3C, bytes[bytes.count - 1] == 0x3E else { return .other }
    // `<!…>`, `<?…>`, `<…/>`.
    if bytes[1] == 0x21 || bytes[1] == 0x3F || bytes[bytes.count - 2] == 0x2F { return .other }
    let closing = bytes[1] == 0x2F
    var name: [UInt8] = []
    for byte in bytes[(closing ? 2 : 1)..<(bytes.count - 1)] {
      if byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D || byte == 0x2F { break }
      name.append(byte)
    }
    guard !name.isEmpty else { return .other }
    return closing ? .end(name) : .start(name)
  }

  /// Whether a run of tokens is balanced XML: every start tag in it closed
  /// in it, in order, and every end tag in it opened in it.
  static func balanced(_ run: [String]) -> Bool {
    var open: [[UInt8]] = []
    for token in run {
      switch tagKind(token) {
      case .start(let name): open.append(name)
      case .end(let name):
        guard let last = open.last, last == name else { return false }
        open.removeLast()
      case .other: break
      }
    }
    return open.isEmpty
  }

  static func same(_ x: String, _ y: String) -> Bool {
    Array(x.utf8) == Array(y.utf8)
  }

  /// Each insertion or deletion standing alone between two equalities,
  /// slid by whole tokens to the earliest place where it is balanced XML;
  /// left where it was if none is.
  static func balancedSlides(_ input: [(Operation, String)]) -> [(Operation, String)] {
    var diffs = input
    var index = 0
    while index < diffs.count {
      let operation = diffs[index].0
      let before = index > 0 ? diffs[index - 1] : nil
      let after = index + 1 < diffs.count ? diffs[index + 1] : nil
      let alone =
        operation != .equal && (before == nil || before!.0 == .equal) && (after == nil || after!.0 == .equal)
      guard alone else {
        index += 1
        continue
      }
      let left = before.map { markupTokens($0.1) } ?? []
      let edit = markupTokens(diffs[index].1)
      let right = after.map { markupTokens($0.1) } ?? []
      // The whole stretch the edit can move in: its left equality, itself,
      // its right one; each place an offset into it.
      let stretch = left + edit + right
      let length = edit.count
      var lowest = left.count
      while lowest > 0 && same(stretch[lowest - 1], stretch[lowest - 1 + length]) { lowest -= 1 }
      var highest = left.count
      while highest + length < stretch.count && same(stretch[highest], stretch[highest + length]) { highest += 1 }
      var chosen: Int? = nil
      var start = lowest
      while start <= highest && chosen == nil {
        if balanced(Array(stretch[start..<(start + length)])) { chosen = start }
        start += 1
      }
      guard let place = chosen, place != left.count else {
        index += 1
        continue
      }
      let newLeft = join(Array(stretch[0..<place]))
      let newEdit = join(Array(stretch[place..<(place + length)]))
      let newRight = join(Array(stretch[(place + length)...]))
      var replacement: [(Operation, String)] = []
      if before != nil || !newLeft.isEmpty { replacement.append((.equal, newLeft)) }
      replacement.append((operation, newEdit))
      if after != nil || !newRight.isEmpty { replacement.append((.equal, newRight)) }
      let from = before == nil ? index : index - 1
      let to = after == nil ? index : index + 1
      diffs.replaceSubrange(from...to, with: replacement)
      index = from + replacement.count - (after == nil ? 0 : 1)
    }
    return merged(diffs)
  }

  /// What a character is to the tokenizer, by the Unicode blocks that hold
  /// it—no Unicode tables, which Embedded Swift does not carry: white space
  /// (ASCII's, and the General Punctuation and CJK spaces); punctuation
  /// (ASCII's, Latin-1's, the General Punctuation, Supplemental
  /// Punctuation, CJK Symbols and Punctuation, and the mathematical white
  /// brackets ⟦⟧ blocks); every other character a word's.
  enum CharacterClass {
    case space, word, punctuation

    init(_ value: UInt32) {
      switch value {
      case 0x20, 0x09, 0x0A, 0x0D, 0x2000...0x200A, 0x202F, 0x205F, 0x3000: self = .space
      // Letters, digits, the underscore.
      case 0x30...0x39, 0x41...0x5A, 0x61...0x7A, 0x5F: self = .word
      case 0x21...0x7E: self = .punctuation
      // Latin-1: ¡ « » ¿ § ¶ · and the rest of its punctuation and signs.
      case 0xA1, 0xA7, 0xAB, 0xB6, 0xB7, 0xBB, 0xBF, 0xD7, 0xF7: self = .punctuation
      // General Punctuation (dashes, quotes, ellipsis, primes…), its
      // format characters (zero-width joiners) aside.
      case 0x2010...0x2027, 0x2030...0x205E: self = .punctuation
      case 0x2E00...0x2E7F, 0x3001...0x3003, 0x3008...0x3011, 0x3014...0x301F, 0x27E6...0x27EF: self = .punctuation
      default: self = .word
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
    for scalar in text.unicodeScalars {
      guard case .space = CharacterClass(scalar.value) else { return false }
    }
    return true
  }

  /// A run of the edit script: something kept, or one change—what it took
  /// out and what it put in, by index.
  enum Group {
    case keep(old: Int, new: Int)
    case change(removed: [Int], added: [Int])
  }

  static func groups(_ script: [Edit]) -> [Group] {
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
    return out
  }

  static func join(_ parts: [String], separator: String = "") -> String {
    var out = ""
    for (index, part) in parts.enumerated() {
      if index > 0 { out += separator }
      out += part
    }
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
    /// How it is set—"italic", "sub"—in a stable order.
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

  /// One line of rendered text: its runs, whether it opens a block—a
  /// paragraph, a verse line, a heading—rather than following a line break,
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
