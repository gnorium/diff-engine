/// A segment of a diff result representing a contiguous run of text
/// that shares the same change status.
public enum DiffSegment: Sendable, Equatable {
  /// Text present in both old and new (no highlighting)
  case unchanged(String)
  /// Specifically deleted word/chars within a deleted line (strong red highlight)
  case deleted(String)
  /// Specifically inserted word/chars within an inserted line (strong green highlight)
  case inserted(String)
  /// Unchanged text on a deleted line (subtle red line background)
  case deletedContext(String)
  /// Unchanged text on an inserted line (subtle green line background)
  case insertedContext(String)

  public var text: String {
    switch self {
    case .unchanged(let t), .inserted(let t), .deleted(let t),
      .deletedContext(let t), .insertedContext(let t):
      return t
    }
  }
}
