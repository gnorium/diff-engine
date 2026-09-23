import Testing

@testable import DiffEngine

@Suite("DiffEngine")
struct DiffEngineTests {

  private func kinds<C>(_ lines: [DiffEngine.Line<C>]) -> String {
    lines.map { line in
      switch line.kind {
      case .unchanged: return "="
      case .removed: return "-"
      case .inserted: return "+"
      }
    }.joined()
  }

  // MARK: - Outline numbers

  /// A number's segments as the diff marks them: changed ones in brackets.
  private func marked(_ segments: [DiffSegment]) -> String {
    segments.map { segment in
      switch segment {
      case .unchanged(let text): return text
      case .changed(let text): return "[\(text)]"
      }
    }.joined()
  }

  @Test func outlineChangesEveryLevelThatChanged() {
    // Not "1.2 → 2.3" with a kept "2": the 2 was the second level and is now
    // the first.
    let pair = DiffEngine.outline(old: "1.2", new: "2.3")
    #expect(marked(pair.old) == "[1.2]")
    #expect(marked(pair.new) == "[2.3]")
  }

  @Test func outlineKeepsUnchangedLevels() {
    let pair = DiffEngine.outline(old: "1.2.1", new: "2.3.1")
    #expect(marked(pair.old) == "[1.2].1")
    #expect(marked(pair.new) == "[2.3].1")
  }

  @Test func outlineChangesOnlyTheLastLevel() {
    let pair = DiffEngine.outline(old: "1.3", new: "1.1")
    #expect(marked(pair.old) == "1[.3]")
    #expect(marked(pair.new) == "1[.1]")
  }

  @Test func outlineLevelsPastTheOtherEndAreChanged() {
    let deeper = DiffEngine.outline(old: "1.2", new: "1.2.1")
    #expect(marked(deeper.old) == "1.2")
    #expect(marked(deeper.new) == "1.2[.1]")
    let shallower = DiffEngine.outline(old: "2.1.3", new: "2")
    #expect(marked(shallower.old) == "2[.1.3]")
    #expect(marked(shallower.new) == "2")
  }

  @Test func outlineComparesLevelsWholeNotByDigit() {
    let pair = DiffEngine.outline(old: "1.12", new: "1.2")
    #expect(marked(pair.old) == "1[.12]")
    #expect(marked(pair.new) == "1[.2]")
  }

  @Test func outlineFromNothing() {
    let pair = DiffEngine.outline(old: "", new: "1.1")
    #expect(pair.old.isEmpty)
    #expect(marked(pair.new) == "[1.1]")
  }

  // MARK: - Text within a line

  @Test func textChangesWordsThenLetters() {
    let pair = DiffEngine.refine(old: "Gold-tooled binding", new: "Gilt-tooled binding")
    #expect(marked(pair.old) == "G[o]l[d]-tooled binding")
    #expect(marked(pair.new) == "G[i]l[t]-tooled binding")
  }

  // MARK: - Source lines

  @Test func identicalTexts() {
    let lines = DiffEngine.lines(old: "a\nb", new: "a\nb")
    #expect(kinds(lines) == "==")
    #expect(DiffEngine.hunks(lines, context: 3).isEmpty)
  }

  @Test func oneLineReplaced() {
    let lines = DiffEngine.lines(old: "one\ntwo\nthree", new: "one\n2\nthree")
    #expect(kinds(lines) == "=-+=")
    #expect(lines[1].content == "two" && lines[1].oldNumber == 2 && lines[1].newNumber == nil)
    #expect(lines[2].content == "2" && lines[2].newNumber == 2 && lines[2].oldNumber == nil)
    #expect(lines[1].note == nil)
  }

  @Test func removalsComeBeforeInsertions() {
    let lines = DiffEngine.lines(old: "a\nb\nc\nd", new: "a\nx\ny\nd")
    #expect(kinds(lines) == "=--++=")
  }

  @Test func emptyTexts() {
    #expect(kinds(DiffEngine.lines(old: "", new: "abc")) == "-+")
    #expect(kinds(DiffEngine.lines(old: "abc", new: "abc\ndef")) == "=+")
  }

  @Test func hunksKeepContextAndSplitFarChanges() {
    let old = (1...20).map { "line \($0)" }
    var new = old
    new[1] = "changed 2"
    new[17] = "changed 18"
    let hunks = DiffEngine.hunks(
      DiffEngine.lines(old: old.joined(separator: "\n"), new: new.joined(separator: "\n")), context: 2)
    #expect(hunks.count == 2)
    #expect(hunks[0].first?.oldNumber == 1)
    #expect(hunks[0].filter(\.isChange).count == 2)
    #expect(hunks[1].last?.newNumber == 20)
  }

  @Test func neverNormalises() {
    // A precomposed é against e + combining acute: different bytes, a changed line.
    let lines = DiffEngine.lines(old: "caf\u{E9}", new: "cafe\u{301}")
    #expect(kinds(lines) == "-+")
    guard case .lookalike? = lines[0].note else {
      Issue.record("expected a look-alike note, got \(String(describing: lines[0].note))")
      return
    }
  }

  @Test func whitespaceOnlyChangeIsNoted() {
    let lines = DiffEngine.lines(old: "of  N units", new: "of N units")
    guard case .spacing? = lines[1].note else {
      Issue.record("expected a spacing note")
      return
    }
  }

  @Test func differentDashesLookAlike() {
    #expect(DiffEngine.looksAlike("1603\u{2013}5", "1603\u{2014}5"))
    #expect(!DiffEngine.looksAlike("\u{17F}leepe", "sleepe"))
  }

  // MARK: - Rendered lines

  private func line(
    _ text: String, _ style: [String] = [], opensBlock: Bool = true, role: String = ""
  ) -> DiffEngine.RenderedLine {
    .init(tokens: [.init(text: text, style: style)], opensBlock: opensBlock, role: role)
  }

  @Test func formattingOnlyChangeIsALinePair() {
    let old = [DiffEngine.RenderedLine(tokens: [.init(text: "of N"), .init(text: "s")])]
    let new = [DiffEngine.RenderedLine(tokens: [.init(text: "of N"), .init(text: "s", style: ["sub"])])]
    let lines = DiffEngine.lines(old: old, new: new)
    #expect(kinds(lines) == "-+")
    #expect(lines[1].content.tokens[1].style == ["sub"])
  }

  @Test func formulaIsAtomic() {
    let old = [DiffEngine.RenderedLine(tokens: [.init(text: "so "), .init(kind: .formula, text: "x^2")])]
    let new = [DiffEngine.RenderedLine(tokens: [.init(text: "so "), .init(kind: .formula, text: "x^3")])]
    let lines = DiffEngine.lines(old: old, new: new)
    #expect(kinds(lines) == "-+")
    #expect(lines[0].content.tokens[1].text == "x^2" && lines[1].content.tokens[1].text == "x^3")
  }

  @Test func splitLineIsOneOutTwoIn() {
    let lines = DiffEngine.lines(
      old: [line("To be or not to be")],
      new: [line("To be or"), line("not to be", opensBlock: false)])
    #expect(kinds(lines) == "-++")
  }

  @Test func breakKindAloneIsNoted() {
    let lines = DiffEngine.lines(
      old: [line("a"), line("b", opensBlock: true)],
      new: [line("a"), line("b", opensBlock: false)])
    #expect(kinds(lines) == "=-+")
    guard case .breakKind? = lines[1].note else {
      Issue.record("expected a break-kind note")
      return
    }
  }

  @Test func renderedSpacingIsNoted() {
    let lines = DiffEngine.lines(old: [line("a  b")], new: [line("a b")])
    guard case .spacing? = lines[0].note else {
      Issue.record("expected a spacing note")
      return
    }
  }

  @Test func renderedLookalikeIsNoted() {
    let lines = DiffEngine.lines(old: [line("1603\u{2013}5")], new: [line("1603\u{2014}5")])
    guard case .lookalike? = lines[0].note else {
      Issue.record("expected a look-alike note")
      return
    }
  }

  @Test func figureRegionIsNoted() {
    let old = [DiffEngine.RenderedLine(tokens: [.init(kind: .figure, text: "Device", style: ["region 1,1,2,2"])])]
    let new = [DiffEngine.RenderedLine(tokens: [.init(kind: .figure, text: "Device", style: ["region 1,1,3,2"])])]
    let lines = DiffEngine.lines(old: old, new: new)
    guard case .region? = lines[0].note else {
      Issue.record("expected a region note")
      return
    }
  }

  @Test func roleIsPartOfTheLine() {
    let lines = DiffEngine.lines(old: [line("Enter", role: "stage")], new: [line("Enter", role: "speaker")])
    #expect(kinds(lines) == "-+")
    #expect(lines[0].content.role == "stage" && lines[1].content.role == "speaker")
  }

  @Test func pageMarkAddedAlone() {
    let lines = DiffEngine.lines(
      old: [line("a"), line("b")],
      new: [line("a"), line("A2 recto", role: "page"), line("b")])
    #expect(kinds(lines) == "=+=")
  }

  // MARK: - Within a line

  @Test func oneLetterCorrectionMarksOneLetter() {
    let pair = DiffEngine.refine(old: "the quick brown fox", new: "the quick brawn fox")
    #expect(pair.old == [.unchanged("the quick br"), .changed("o"), .unchanged("wn fox")])
    #expect(pair.new == [.unchanged("the quick br"), .changed("a"), .unchanged("wn fox")])
  }

  @Test func rewrittenWordIsMarkedWhole() {
    let pair = DiffEngine.refine(old: "an alpha test", new: "an zulu test")
    #expect(pair.old == [.unchanged("an "), .changed("alpha"), .unchanged(" test")])
    #expect(pair.new == [.unchanged("an "), .changed("zulu"), .unchanged(" test")])
  }

  @Test func spaceBetweenChangesIsFolded() {
    let pair = DiffEngine.refine(old: "the old grey cat", new: "the new white cat")
    #expect(pair.old == [.unchanged("the "), .changed("old grey"), .unchanged(" cat")])
    #expect(pair.new == [.unchanged("the "), .changed("new white"), .unchanged(" cat")])
  }

  @Test func attributeValueChangeIsInsideTheTag() {
    let pair = DiffEngine.refine(old: "<hi rend=\"sub\">s</hi>", new: "<hi rend=\"sup\">s</hi>")
    #expect(pair.old.contains(.changed("b")))
    #expect(pair.new.contains(.changed("p")))
  }

  @Test func whitespaceChangeIsMarked() {
    let pair = DiffEngine.refine(old: "of  N", new: "of N")
    #expect(pair.old == [.unchanged("of "), .changed(" "), .unchanged("N")])
    #expect(pair.new == [.unchanged("of N")])
  }

  @Test func pairedLinesCarryRefinedSegments() {
    let lines = DiffEngine.lines(old: "keep\nof N units", new: "keep\nof M units")
    #expect(lines[1].segments == [.unchanged("of "), .changed("N"), .unchanged(" units")])
    #expect(lines[2].segments == [.unchanged("of "), .changed("M"), .unchanged(" units")])
    #expect(lines[0].segments == [.unchanged("keep")])
  }

  @Test func unpairedLinesAreWhollyChanged() {
    let lines = DiffEngine.lines(old: "a", new: "a\nb\nc")
    #expect(lines[1].segments == [.changed("b")])
    #expect(lines[2].segments == [.changed("c")])
  }

  @Test func pairingFollowsOrderWithinAChange() {
    let lines = DiffEngine.lines(old: "x\none\ntwo\ny", new: "x\n1ne\ntwo!\nthree\ny")
    #expect(kinds(lines) == "=--+++=")
    #expect(lines[3].segments == [.changed("1"), .unchanged("ne")])
    #expect(lines[4].segments == [.unchanged("two"), .changed("!")])
    #expect(lines[5].segments == [.changed("three")])
  }

  @Test func lookalikeCharacterIsTheChange() {
    let pair = DiffEngine.refine(old: "1603\u{2013}5", new: "1603\u{2014}5")
    #expect(pair.old.contains(.changed("\u{2013}")))
    #expect(pair.new.contains(.changed("\u{2014}")))
  }

  @Test func renderedLinesAreRefinedOnTheirText() {
    let old = [DiffEngine.RenderedLine(tokens: [.init(text: "of N"), .init(text: "s", style: ["sub"])])]
    let new = [DiffEngine.RenderedLine(tokens: [.init(text: "of M"), .init(text: "s", style: ["sub"])])]
    let lines = DiffEngine.lines(old: old, new: new)
    #expect(lines[0].segments == [.unchanged("of "), .changed("N"), .unchanged("s")])
  }
}
