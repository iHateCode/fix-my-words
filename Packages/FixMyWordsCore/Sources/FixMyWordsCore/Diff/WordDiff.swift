public struct DiffSpan: Equatable, Sendable {
    public enum Kind: Sendable { case same, removed, added }
    public let kind: Kind
    public let text: String
}

public enum WordDiff {
    /// Selections longer than this skip the highlighted view and show the plain result.
    public static let maxHighlightLength = 20_000

    /// Splits into words and the whitespace between them, so spacing survives, then diffs the tokens.
    public static func spans(from old: String, to new: String) -> [DiffSpan] {
        let a = tokens(old), b = tokens(new)
        let changes = b.difference(from: a)
        var removed = Set<Int>(), added = Set<Int>()
        for change in changes {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): added.insert(offset)
            }
        }
        var spans: [DiffSpan] = []
        var i = 0, j = 0
        while i < a.count || j < b.count {
            if i < a.count, removed.contains(i) { spans.append(.init(kind: .removed, text: a[i])); i += 1 }
            else if j < b.count, added.contains(j) { spans.append(.init(kind: .added, text: b[j])); j += 1 }
            else { spans.append(.init(kind: .same, text: b[j])); i += 1; j += 1 }
        }
        return merged(spans)
    }

    static func tokens(_ s: String) -> [String] {
        s.matches(of: /\s+|\S+/).map { String($0.output) }
    }

    static func merged(_ spans: [DiffSpan]) -> [DiffSpan] {
        spans.reduce(into: []) { out, span in
            if let last = out.last, last.kind == span.kind { out[out.count - 1] = .init(kind: span.kind, text: last.text + span.text) }
            else { out.append(span) }
        }
    }
}
