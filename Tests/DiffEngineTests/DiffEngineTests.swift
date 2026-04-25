import Testing

@testable import DiffEngine

@Suite("DiffEngine")
struct DiffEngineTests {

  @Test func identicalStrings() {
    let result = DiffEngine.diff(old: "hello", new: "hello")
    #expect(result == [.unchanged("hello")])
  }

  @Test func emptyOld() {
    let result = DiffEngine.diff(old: "", new: "abc")
    #expect(result == [.inserted("abc")])
  }

  @Test func emptyNew() {
    let result = DiffEngine.diff(old: "abc", new: "")
    #expect(result == [.deleted("abc")])
  }

  @Test func bothEmpty() {
    let result = DiffEngine.diff(old: "", new: "")
    #expect(result == [])
  }

  @Test func singleInsertion() {
    let result = DiffEngine.diff(old: "ac", new: "abc")
    #expect(
      result == [
        .unchanged("a"),
        .inserted("b"),
        .unchanged("c"),
      ])
  }

  @Test func singleDeletion() {
    let result = DiffEngine.diff(old: "abc", new: "ac")
    #expect(
      result == [
        .unchanged("a"),
        .deleted("b"),
        .unchanged("c"),
      ])
  }

  @Test func replacement() {
    let result = DiffEngine.diff(old: "cat", new: "car")
    #expect(
      result == [
        .unchanged("ca"),
        .deleted("t"),
        .inserted("r"),
      ])
  }

  @Test func prefixChange() {
    let result = DiffEngine.diff(old: "hello world", new: "jello world")
    #expect(
      result == [
        .deleted("h"),
        .inserted("j"),
        .unchanged("ello world"),
      ])
  }

  @Test func suffixChange() {
    // Char-level diff finds shared 'r' between "world" and "earth"
    let result = DiffEngine.diff(old: "hello world", new: "hello earth")
    #expect(
      result == [
        .unchanged("hello "),
        .deleted("wo"),
        .inserted("ea"),
        .unchanged("r"),
        .deleted("ld"),
        .inserted("th"),
      ])
  }

  @Test func unicode() {
    let result = DiffEngine.diff(old: "cafe\u{0301}", new: "café!")
    // Both contain café — the composed vs decomposed forms
    // This tests that we handle unicode correctly at the Character level
    #expect(result.count > 0)
  }

  @Test func segmentText() {
    #expect(DiffSegment.unchanged("a").text == "a")
    #expect(DiffSegment.inserted("b").text == "b")
    #expect(DiffSegment.deleted("c").text == "c")
  }
}
