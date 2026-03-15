import Foundation

final class LocalTextProcessor: Sendable {
    // Only remove obvious fillers — don't over-process since Apple Speech already handles punctuation/caps
    private let fillerPattern: NSRegularExpression
    private let stutterPattern: NSRegularExpression
    private let multiSpacePattern: NSRegularExpression

    init() {
        // Only clear filler words (not "like" which is often intentional)
        fillerPattern = try! NSRegularExpression(
            pattern: "\\b(?:um|uh|umm|uhh|erm|hmm)\\b,?\\s*",
            options: .caseInsensitive
        )

        // Repeated words: "I I", "the the"
        stutterPattern = try! NSRegularExpression(
            pattern: "\\b(\\w+)(?:\\s+\\1)+\\b",
            options: .caseInsensitive
        )

        multiSpacePattern = try! NSRegularExpression(pattern: " {2,}", options: [])
    }

    func process(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return text }

        // 1. Remove filler words only
        text = fillerPattern.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..., in: text), withTemplate: ""
        )

        // 2. Remove stutters
        text = stutterPattern.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "$1"
        )

        // 3. Collapse spaces
        text = multiSpacePattern.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " "
        )

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
