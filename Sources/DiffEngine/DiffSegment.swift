/// A segment of a diff result representing a contiguous run of characters
/// that share the same change status.
public enum DiffSegment: Sendable, Equatable {
	/// Text present in both old and new
	case unchanged(String)
	/// Text present only in new (added)
	case inserted(String)
	/// Text present only in old (removed)
	case deleted(String)

	public var text: String {
		switch self {
		case .unchanged(let t), .inserted(let t), .deleted(let t):
			return t
		}
	}
}
