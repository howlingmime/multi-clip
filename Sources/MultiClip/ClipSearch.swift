import Foundation

/// Ranked fuzzy search over the clip history.
///
/// A query is tokenized on whitespace and path/identifier punctuation, so `src/app.swift`
/// searches as `src`, `app`, `swift`. Every query token must match a clip for it to survive;
/// the per-token match quality (exact word > word prefix > substring > fuzzy subsequence)
/// is summed into a score used to order the results.
enum ClipSearch {
    /// Characters that end a word. Doubles as the path splitter, so file-URL clips are
    /// searchable by any single path component.
    static let separators: Set<Character> = [
        " ", "\t", "\n", "\r", "/", "\\", ".", "_", "-", ":", ";", ",",
        "(", ")", "[", "]", "{", "}", "<", ">", "\"", "'", "`",
        "=", "?", "&", "#", "|", "@", "+", "*", "!", "~", "$", "%", "^"
    ]

    /// Longest prefix of a clip considered for fuzzy (subsequence) matching. Exact and
    /// substring matching still see the whole haystack; this only bounds the O(n) scan.
    private static let fuzzyScanLimit = 4_000

    static func tokenize(_ s: String) -> [String] {
        s.lowercased().split(whereSeparator: { separators.contains($0) }).map(String.init)
    }

    /// Clips matching every token of `query`, best match first. An empty query returns
    /// `clips` untouched so the caller can apply its own default ordering.
    static func rank(_ clips: [Clip], query: String) -> [Clip] {
        let needles = tokenize(query.trimmingCharacters(in: .whitespaces))
        guard !needles.isEmpty else { return clips }

        var scored: [(clip: Clip, score: Int)] = []
        scored.reserveCapacity(clips.count)
        for clip in clips {
            guard let score = score(clip, needles: needles) else { continue }
            scored.append((clip, score))
        }
        return scored.sorted { a, b in
            if a.score != b.score { return a.score > b.score }
            if a.clip.pinned != b.clip.pinned { return a.clip.pinned }
            return a.clip.capturedAt > b.clip.capturedAt
        }.map(\.clip)
    }

    /// Total score for a clip, or nil when any token fails to match.
    static func score(_ clip: Clip, needles: [String]) -> Int? {
        let hay = clip.searchHaystack.lowercased()
        let hayTokens = tokenize(hay)
        let name = (clip.name ?? "").lowercased()

        var total = 0
        for needle in needles {
            guard let s = tokenScore(needle, hay: hay, hayTokens: hayTokens, name: name) else { return nil }
            total += s
        }
        // Snippets are deliberately kept around, so surface them above transient clips
        // of otherwise equal relevance.
        if clip.pinned { total += 25 }
        return total
    }

    private static func tokenScore(_ needle: String, hay: String, hayTokens: [String], name: String) -> Int? {
        var score: Int
        if hayTokens.contains(needle) {
            score = 100
        } else if hayTokens.contains(where: { $0.hasPrefix(needle) }) {
            score = 80
        } else if hay.contains(needle) {
            score = 60
        } else if let bonus = fuzzy(needle, in: hay) {
            score = 20 + bonus
        } else {
            return nil
        }
        // A hit in a snippet's name is what the user typed it for.
        if !name.isEmpty, name.contains(needle) { score += 40 }
        return score
    }

    /// Greedy subsequence match: every character of `needle` must appear in `hay` in order.
    /// Returns a bonus rewarding contiguous runs and word-boundary starts, or nil if unmatched.
    static func fuzzy(_ needle: String, in hay: String) -> Int? {
        guard !needle.isEmpty else { return nil }
        var bonus = 0
        var streak = 0
        var atWordStart = true
        var idx = hay.startIndex
        let limit = hay.index(hay.startIndex, offsetBy: fuzzyScanLimit, limitedBy: hay.endIndex) ?? hay.endIndex

        for ch in needle {
            var matched = false
            while idx < limit {
                let h = hay[idx]
                idx = hay.index(after: idx)
                if h == ch {
                    bonus += 2
                    if atWordStart { bonus += 6 }
                    streak += 1
                    bonus += min(streak, 5)
                    atWordStart = separators.contains(h)
                    matched = true
                    break
                }
                streak = 0
                atWordStart = separators.contains(h)
            }
            if !matched { return nil }
        }
        return min(bonus, 40)
    }
}
