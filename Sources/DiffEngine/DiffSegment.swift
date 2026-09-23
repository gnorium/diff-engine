/// A stretch of a line that shares one fate against the line it is paired
/// with: kept, or changed.
public enum DiffSegment: Sendable {
  case unchanged(String)
  case changed(String)

  public var text: String {
    switch self {
    case .unchanged(let t), .changed(let t): return t
    }
  }
}

#if SERVER
  extension DiffSegment: Equatable {}
#endif
