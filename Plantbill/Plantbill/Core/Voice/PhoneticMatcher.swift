import Foundation

/// Indian-English phonetic matcher, ported line-for-line from Android's
/// `ui/billing/voice/PhoneticMatcher.kt` (itself a port of the web app's
/// VoiceSearchButton.tsx). Maps a noisy voice transcript to the closest
/// product name. Pure and testable — `PhoneticMatcherChecks` exercises the
/// same cases as the Kotlin unit test so the two stay in step.
enum PhoneticMatcher {

    struct Match: Equatable {
        let candidate: String
        let score: Double
    }

    /// Forgiving confidence floor — snap noisy speech to the nearest plant name.
    private static let threshold = 0.12

    /// Consonant-based phonetic key for a single word, handling common Indian
    /// English mergers (v/w, s/sh, z/s, …) and dropping vowels after the first.
    static func phoneticCode(_ word: String) -> String {
        var w = word.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if w.isEmpty { return "" }

        if w.hasPrefix("x") { w = "z" + w.dropFirst() }

        // Order matters and mirrors the Kotlin chain exactly: the digraph
        // rules run before the single-letter ones, so e.g. "ch" ends up "kh"
        // rather than being folded by the earlier "kh" rule.
        w = w.replacingOccurrences(of: "ph", with: "f")
            .replacingOccurrences(of: "gh", with: "g")
            .replacingOccurrences(of: "kh", with: "k")
            .replacingOccurrences(of: "sh", with: "s")
            .replacingOccurrences(of: "w", with: "v")
            .replacingOccurrences(of: "c", with: "k")
            .replacingOccurrences(of: "q", with: "k")
            .replacingOccurrences(of: "z", with: "s")
            .replacingOccurrences(of: "y", with: "i")

        // Drop consecutive duplicate letters.
        var dedup = ""
        for (i, ch) in w.enumerated() {
            if i == 0 || ch != dedup.last { dedup.append(ch) }
        }
        w = dedup

        if w.count <= 1 { return w }
        let first = w.first!
        let rest = w.dropFirst().filter { !"aeiou".contains($0) }
        return String(first) + rest
    }

    private static func words(_ s: String) -> [String] {
        s.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    private static func phoneticMatchScore(_ a: String, _ b: String) -> Double {
        let w1 = Set(words(a).map(phoneticCode).filter { !$0.isEmpty })
        let w2 = Set(words(b).map(phoneticCode).filter { !$0.isEmpty })
        if w1.isEmpty || w2.isEmpty { return 0 }
        let intersection = w1.filter { w2.contains($0) }.count
        let union = w1.count + w2.count - intersection
        return union > 0 ? Double(intersection) / Double(union) : 0
    }

    /// Similarity of a spoken phrase to one product name, combining exact /
    /// substring / word-overlap / phonetic / edit-distance heuristics. 0...1.
    static func score(transcript: String, candidate: String) -> Double {
        let text = transcript.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let cand = candidate.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty || cand.isEmpty { return 0 }
        if text == cand { return 1 }

        if cand.contains(text) || text.contains(cand) {
            let shorter = Double(min(text.count, cand.count))
            let longer = Double(max(text.count, cand.count))
            return 0.8 + 0.15 * (shorter / longer)
        }

        let wordsText = Set(words(text))
        let wordsCand = Set(words(cand))
        let inter = wordsText.filter { wordsCand.contains($0) }.count
        let union = wordsText.count + wordsCand.count - inter
        let wordScore = union > 0 ? (Double(inter) / Double(union)) * 0.9 : 0

        let phon = phoneticMatchScore(text, cand) * 0.95

        let dist = levenshtein(text, cand)
        let maxLen = max(text.count, cand.count)
        let lev = maxLen > 0 ? (1 - Double(dist) / Double(maxLen)) * 0.85 : 0

        return max(wordScore, max(phon, lev))
    }

    /// Best matching candidate above the confidence threshold, or nil.
    static func findBestMatch(transcript: String, candidates: [String]) -> Match? {
        guard let m = findClosest(transcript: transcript, candidates: candidates) else { return nil }
        return m.score > threshold ? m : nil
    }

    /// The single closest product name to what was spoken — ALWAYS returns a
    /// plant when the catalog isn't empty, with no confidence floor. The mic is
    /// restricted to the shop's own products, so any utterance snaps to the
    /// nearest plant name instead of leaking arbitrary words into a text search.
    static func findClosest(transcript: String, candidates: [String]) -> Match? {
        guard let first = candidates.first else { return nil }
        var best = first
        var highest = -1.0
        for candidate in candidates {
            let s = score(transcript: transcript, candidate: candidate)
            if s > highest { highest = s; best = candidate }
        }
        return Match(candidate: best, score: highest)
    }

    static func levenshtein(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        let an = x.count, bn = y.count
        if an == 0 { return bn }
        if bn == 0 { return an }
        var prev = Array(0...bn)
        var cur = [Int](repeating: 0, count: bn + 1)
        for i in 1...an {
            cur[0] = i
            for j in 1...bn {
                let cost = x[i - 1] == y[j - 1] ? 0 : 1
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
            }
            prev = cur
        }
        return prev[bn]
    }
}
