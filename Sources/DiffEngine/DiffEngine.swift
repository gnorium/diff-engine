/// Character-level diff engine using Swift's `CollectionDifference`.
/// Pure Swift, zero dependencies — works on all Apple platforms, Linux, and WASM.
public enum DiffEngine {

	/// Computes a character-level diff between two strings.
	/// Returns an array of `DiffSegment` values representing unchanged, inserted,
	/// and deleted runs of text in document order.
	public static func diff(old: String, new: String) -> [DiffSegment] {
		if old == new { return old.isEmpty ? [] : [.unchanged(old)] }
		if old.isEmpty { return [.inserted(new)] }
		if new.isEmpty { return [.deleted(old)] }

		let oldChars = Array(old)
		let newChars = Array(new)

		let difference = newChars.difference(from: oldChars)

		// Build index sets for O(1) lookup
		var removedIndices = Set<Int>()
		var insertedIndices = Set<Int>()

		for change in difference {
			switch change {
			case .remove(let offset, _, _):
				removedIndices.insert(offset)
			case .insert(let offset, _, _):
				insertedIndices.insert(offset)
			}
		}

		// Walk both strings in parallel, building typed character operations.
		// Deleted chars (from old) come first at each position, then inserted (from new),
		// then the unchanged char advances both pointers.
		var operations: [(Kind, Character)] = []
		operations.reserveCapacity(max(oldChars.count, newChars.count))

		var oi = 0
		var ni = 0

		while oi < oldChars.count || ni < newChars.count {
			while oi < oldChars.count && removedIndices.contains(oi) {
				operations.append((.deleted, oldChars[oi]))
				oi += 1
			}

			while ni < newChars.count && insertedIndices.contains(ni) {
				operations.append((.inserted, newChars[ni]))
				ni += 1
			}

			if oi < oldChars.count && ni < newChars.count {
				operations.append((.unchanged, newChars[ni]))
				oi += 1
				ni += 1
			}
		}

		return coalesce(operations)
	}

	// MARK: - Internal

	private enum Kind { case unchanged, inserted, deleted }

	/// Coalesces consecutive same-kind operations into `DiffSegment` values.
	private static func coalesce(_ operations: [(Kind, Character)]) -> [DiffSegment] {
		guard let first = operations.first else { return [] }

		var segments: [DiffSegment] = []
		var currentKind = first.0
		var currentChars: [Character] = [first.1]

		for i in 1..<operations.count {
			let (kind, char) = operations[i]
			if kind == currentKind {
				currentChars.append(char)
			} else {
				segments.append(segment(currentKind, String(currentChars)))
				currentKind = kind
				currentChars = [char]
			}
		}
		segments.append(segment(currentKind, String(currentChars)))

		return segments
	}

	private static func segment(_ kind: Kind, _ text: String) -> DiffSegment {
		switch kind {
		case .unchanged: .unchanged(text)
		case .inserted: .inserted(text)
		case .deleted: .deleted(text)
		}
	}
}
