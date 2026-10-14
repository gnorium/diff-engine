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

  @Test func anEmptyTextHasNoLines() {
    // A page that had no markup: every line added, no removed blank line.
    let lines = DiffEngine.lines(old: "", new: "<pb/>\n<p>a</p>")
    #expect(lines.count == 2)
    #expect(DiffEngine.lines(old: "", new: "").isEmpty)
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

  @Test func aChangedWordIsMarkedWhole() {
    let pair = DiffEngine.refine(old: "Gold-tooled binding", new: "Gilt-tooled binding")
    #expect(marked(pair.old) == "[Gold]-tooled binding")
    #expect(marked(pair.new) == "[Gilt]-tooled binding")
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

  @Test func pairedLinesMarkTheirTokens() {
    // Paired as any k-th removed and k-th added line are, no threshold:
    // the tokens that differ marked, the ones both keep not.
    let old = "• footnotes\u{2014}footnotes: <note place=\"foot\">"
    let new = "• provenance\u{2014}marks this copy\u{2019}s owners or keepers added: <provenance>"
    let lines = DiffEngine.lines(old: "a\n\(old)\nz", new: "a\n\(new)\nz")
    #expect(kinds(lines) == "=-+=")
    // Whole tokens, and the short kept dash, colon and space between the
    // changes folded into one change (diff-match-patch's semantic cleanup).
    #expect(marked(lines[1].segments) == "• [footnotes—footnotes: <note place=\"foot\"]>")
    #expect(marked(lines[2].segments) == "• [provenance—marks this copy’s owners or keepers added: <provenance]>")
  }

  @Test func similarLinesArePaired() {
    let lines = DiffEngine.lines(old: "Gold-tooled binding", new: "Gilt-tooled binding")
    #expect(marked(lines[0].segments) == "[Gold]-tooled binding")
    #expect(marked(lines[1].segments) == "[Gilt]-tooled binding")
  }

  @Test func aRewrittenPhraseIsMarkedWholeNotByScatteredLetters() {
    let pair = DiffEngine.refine(
      old: "it spans; blank lines left inside a block are <space/>.",
      new: "it spans. Where the page leaves a visible vertical gap within its text, record it with <space/>.")
    // One change: the spaces and the "a" kept between the changed words
    // are shorter than the edits around them, and fold into them.
    #expect(marked(pair.old) == "it spans[; blank lines left inside a block are] <space/>.")
  }

  @Test func aLineThatGrewMarksOnlyWhatWasAdded() {
    let lines = DiffEngine.lines(
      old: "It spans; blank lines are <space/>. Never type extra spaces.",
      new: "It spans. Where the page leaves a vertical gap within its text, record it with <space/>. Never type extra spaces.")
    #expect(kinds(lines) == "-+")
    #expect(marked(lines[0].segments).hasPrefix("It spans"))
    #expect(marked(lines[1].segments).hasPrefix("It spans"))
  }

  @Test func dissimilarFirstPairDoesNotStopTheNext() {
    let lines = DiffEngine.lines(old: "alpha beta\nthe quick fox", new: "zzzz\nthe quick cat")
    #expect(kinds(lines) == "--++")
    #expect(marked(lines[0].segments) == "[alpha beta]")
    #expect(marked(lines[2].segments) == "[zzzz]")
    #expect(marked(lines[1].segments) == "the quick [fox]")
  }

  @Test func aLinePutInBeforeAChangedOneLeavesItsPartner() {
    // A bullet added above one whose word changed: the changed bullet is
    // paired with its old self, its one word marked; the new one is whole.
    let lines = DiffEngine.lines(
      old: "- Keep every line break as printed on the page.",
      new: "- Record the provenance of this copy.\n- Keep every line end as printed on the page.")
    #expect(kinds(lines) == "-++")
    #expect(marked(lines[0].segments) == "- Keep every line [break] as printed on the page.")
    #expect(marked(lines[1].segments) == "[- Record the provenance of this copy.]")
    #expect(marked(lines[2].segments) == "- Keep every line [end] as printed on the page.")
  }

  @Test func reorderedChangesPairByLikeness() {
    let lines = DiffEngine.lines(
      old: "alpha beta gamma delta\nthe quick brown fox jumps",
      new: "a new opening line entirely\nalpha beta gamma epsilon\nthe quick brown fox leaps")
    #expect(kinds(lines) == "--+++")
    #expect(marked(lines[0].segments) == "alpha beta gamma [delta]")
    #expect(marked(lines[3].segments) == "alpha beta gamma [epsilon]")
    #expect(marked(lines[4].segments) == "the quick brown fox [leaps]")
  }

  @Test func lookalikeShortLinesStillPair() {
    let lines = DiffEngine.lines(old: "\u{2013}", new: "\u{2014}")
    guard case .lookalike? = lines[0].note else {
      Issue.record("expected a look-alike note")
      return
    }
  }

  @Test func removalsComeBeforeInsertions() {
    let lines = DiffEngine.lines(old: "a\nb\nc\nd", new: "a\nx\ny\nd")
    #expect(kinds(lines) == "=--++=")
  }

  @Test func emptyTexts() {
    // No text is no lines: an empty old text diffs as all added.
    #expect(kinds(DiffEngine.lines(old: "", new: "abc")) == "+")
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

  @Test func anOCRLetterCorrectionMarksItsWord() {
    // Whole tokens, as git's word diff marks them (user, 2026-10-11).
    let pair = DiffEngine.refine(old: "the quick brown fox", new: "the quick brawn fox")
    #expect(pair.old == [.unchanged("the quick "), .changed("brown"), .unchanged(" fox")])
    #expect(pair.new == [.unchanged("the quick "), .changed("brawn"), .unchanged(" fox")])
  }

  @Test func oneWordForOneWordIsMarkedWhole() {
    let pair = DiffEngine.refine(old: "an alpha test", new: "an zulu test")
    #expect(pair.old == [.unchanged("an "), .changed("alpha"), .unchanged(" test")])
    #expect(pair.new == [.unchanged("an "), .changed("zulu"), .unchanged(" test")])
  }

  @Test func wordsChangedAroundAKeptSpaceAreOneChange() {
    // The space kept between them is shorter than the edits on both sides:
    // folded in (cleanupSemantic).
    let pair = DiffEngine.refine(old: "the old grey cat", new: "the new white cat")
    #expect(pair.old == [.unchanged("the "), .changed("old grey"), .unchanged(" cat")])
    #expect(pair.new == [.unchanged("the "), .changed("new white"), .unchanged(" cat")])
  }

  @Test func aReorderedListReadsAsRunsNotScatteredLetters() {
    // The prompt's color list, reordered and extended (user, 2026-10-11): no
    // letters marked inside words ("w[hite]" → "[b]rown"), and the kept
    // commas and spaces between changed names do not cut the runs apart.
    let pair = DiffEngine.refine(
      old: "white, gray, red, orange, yellow, green",
      new: "pink, red, orange, brown, yellow, olive, yellow-green, green")
    #expect(marked(pair.old) == "[white, gray], red, orange[, yellow], green")
    #expect(marked(pair.new) == "[pink], red, orange[, brown, yellow, olive, yellow-green], green")
  }

  @Test func attributeValueChangeIsInsideTheTag() {
    let pair = DiffEngine.refine(old: "<hi rend=\"sub\">s</hi>", new: "<hi rend=\"sup\">s</hi>")
    #expect(marked(pair.old) == "<hi rend=\"[sub]\">s</hi>")
    #expect(marked(pair.new) == "<hi rend=\"[sup]\">s</hi>")
  }

  @Test func whitespaceChangeIsMarked() {
    let pair = DiffEngine.refine(old: "of  N", new: "of N")
    #expect(pair.old == [.unchanged("of"), .changed("  "), .unchanged("N")])
    #expect(pair.new == [.unchanged("of"), .changed(" "), .unchanged("N")])
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
    #expect(lines[3].segments == [.changed("1ne")])
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
    // "N" and its subscript "s" read as one word, "Ns": marked whole.
    #expect(lines[0].segments == [.unchanged("of "), .changed("Ns")])
  }

  // MARK: - Re-broken lines

  /// A line's text as the diff marks it, changed stretches in brackets, a
  /// changed break as "⏎".
  private func marks<C>(_ lines: [DiffEngine.Line<C>]) -> [String] {
    lines.map { line in
      let kind = line.kind == .removed ? "-" : (line.kind == .inserted ? "+" : "=")
      return kind + marked(line.segments) + (line.breakChanged ? "[⏎]" : "")
    }
  }

  @Test func indentationAloneMarksOnlyTheSpaces() {
    let lines = DiffEngine.lines(old: "<s>\n<w>a</w>\n</s>", new: "<s>\n  <w>a</w>\n</s>")
    #expect(marks(lines) == ["=<s>", "-<w>a</w>", "+[  ]<w>a</w>", "=</s>"])
  }

  @Test func oneLineReflowedMarksOnlyTheBreaksAndIndent() {
    let lines = DiffEngine.lines(
      old: "<s><w>AN</w> <w>ETYMOLOGICAL</w><lb/></s>",
      new: "<s>\n  <w>AN</w>\n  <w>ETYMOLOGICAL</w>\n  <lb/>\n</s>")
    #expect(
      marks(lines) == [
        // The space that stood between the words is taken out, and each new
        // line's indent is new: white space is marked whole, as a token.
        "-<s><w>AN</w>[ ]<w>ETYMOLOGICAL</w><lb/></s>",
        "+<s>[⏎]", "+[  ]<w>AN</w>[⏎]", "+[  ]<w>ETYMOLOGICAL</w>[⏎]", "+[  ]<lb/>[⏎]", "+</s>",
      ])
    for line in lines { #expect(line.note.map { "\($0)" } == "spacing") }
  }

  @Test func severalLinesJoinedMarkOnlyTheBreaksTakenOut() {
    let lines = DiffEngine.lines(old: "a\n  b", new: "a b")
    #expect(marks(lines) == ["-a[⏎]", "-[  ]b", "+a[ ]b"])
  }

  @Test func aReflowWithAnEditPairsItsLines() {
    // Its text changed, so it is no reflow: its lines are paired one by one.
    let lines = DiffEngine.lines(old: "<w>Been</w> <w>thus</w>", new: "<w>Been</w>\n<w>thys</w>")
    #expect(marks(lines) == ["-<w>Been</w>[ <w>thus</w>]", "+<w>Been</w>", "+[<w>thys</w>]"])
  }

  @Test func aDashClosedUpMarksTheSpacesAroundIt() {
    let pair = DiffEngine.refine(old: "documents — manuscripts", new: "documents—manuscripts")
    // The kept dash, shorter than the spaces taken out on either side, is
    // folded into one change.
    #expect(pair.old == [.unchanged("documents"), .changed(" — "), .unchanged("manuscripts")])
    #expect(pair.new == [.unchanged("documents"), .changed("—"), .unchanged("manuscripts")])
  }

  // MARK: - Markup

  @Test func anInsertionIsMarkedWhereItIsBalancedXML() {
    // The sample (user, 2026-10-12): `thoroughly</w> <w>` read the same but
    // cut across tags; the earliest balanced place is ` <w>thoroughly</w>`.
    let old = "<l><w>The</w> <w>text</w> <w>has</w> <w>in</w> <w>the</w> <w>meantime</w> <w>been</w> <w>revised</w></l>"
    let new =
      "<l><w>The</w> <w>text</w> <w>since</w> <w>has</w> <w>in</w> <w>the</w> <w>meantime</w> <w>been</w> <w>thoroughly</w> <w>revised</w></l>"
    let pair = DiffEngine.refine(old: old, new: new, markup: true)
    #expect(marked(pair.old) == old)
    #expect(
      marked(pair.new)
        == "<l><w>The</w> <w>text</w>[ <w>since</w>] <w>has</w> <w>in</w> <w>the</w> <w>meantime</w> <w>been</w>[ <w>thoroughly</w>] <w>revised</w></l>"
    )
  }

  @Test func aDeletedElementIsMarkedWhole() {
    let pair = DiffEngine.refine(old: "<p>a <hi>b</hi> c</p>", new: "<p>a c</p>", markup: true)
    #expect(marked(pair.old) == "<p>a[ <hi>b</hi>] c</p>")
    #expect(marked(pair.new) == "<p>a c</p>")
  }

  @Test func aTagWithAnAttributeAddedIsChangedWhole() {
    // A tag is one token: its new attribute marks the tag, never part of it.
    let pair = DiffEngine.refine(old: "<hi>x</hi>", new: "<hi rend=\"italic\">x</hi>", markup: true)
    #expect(marked(pair.old) == "[<hi>]x</hi>")
    #expect(marked(pair.new) == "[<hi rend=\"italic\">]x</hi>")
  }

  @Test func anInsertionWithNoBalancedPlaceStaysWhereItWas() {
    // Every place `<x>a` or `a<x>` can take opens a tag it never closes:
    // the diff's own choice stands.
    let old = "<x>a<x>"
    let new = "<x>a<x>a<x>"
    let balancedPair = DiffEngine.refine(old: old, new: new, markup: true)
    let plain = DiffEngine.cleanupSemantic(
      DiffEngine.merged(
        DiffEngine.edits(
          old: DiffEngine.markupTokens(old).map { Array($0.utf8) },
          new: DiffEngine.markupTokens(new).map { Array($0.utf8) }
        ).map { edit -> (DiffEngine.Operation, String) in
          switch edit {
          case .keep(let i, _): return (.equal, DiffEngine.markupTokens(old)[i])
          case .delete(let i): return (.delete, DiffEngine.markupTokens(old)[i])
          case .insert(let j): return (.insert, DiffEngine.markupTokens(new)[j])
          }
        }))
    let expected = plain.filter { $0.0 != .delete }.map { $0.0 == .equal ? $0.1 : "[\($0.1)]" }.joined()
    #expect(marked(balancedPair.new) == expected)
    #expect(marked(balancedPair.new).contains("["))
  }

  @Test func plainTextIsUnaffected() {
    // Without `markup`, a tag's attribute value is its own token, as before.
    let pair = DiffEngine.refine(old: "<hi rend=\"a\">x</hi>", new: "<hi rend=\"b\">x</hi>")
    #expect(marked(pair.new) == "<hi rend=\"[b]\">x</hi>")
  }
}

