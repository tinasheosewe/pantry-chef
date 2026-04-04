import Foundation

// Bitap (shift-or) fuzzy substring search.
// Adapted from Fuse-Swift by Kirollos Risk, MIT License.
// See THIRD_PARTY_LICENSES.md for attribution.

/// Performs fuzzy substring matching using the bitap (shift-or) algorithm.
/// Given a short pattern, finds approximate occurrences inside a longer text
/// and returns a score (0 = perfect, 1 = no match).
enum BitapSearcher {

    struct Match {
        /// 0.0 = perfect match, 1.0 = no match.
        let score: Double
    }

    /// Maximum pattern length supported by the bitap algorithm (limited by
    /// the width of `Int` on the platform — 63 on 64-bit).
    static let maxPatternLength = 32

    // MARK: - Pattern

    struct Pattern {
        let text: String
        let length: Int
        let mask: Int
        let alphabet: [Character: Int]
    }

    static func createPattern(from text: String) -> Pattern? {
        let lowered = text.lowercased()
        guard !lowered.isEmpty, lowered.count <= maxPatternLength else { return nil }
        return Pattern(
            text: lowered,
            length: lowered.count,
            mask: 1 << (lowered.count - 1),
            alphabet: buildAlphabet(lowered)
        )
    }

    // MARK: - Search

    /// Searches for `pattern` in `text`, allowing up to `maxErrors` mismatches.
    /// Returns `nil` when no acceptable match is found.
    static func search(
        _ pattern: Pattern,
        in text: String,
        threshold: Double = 0.6,
        distance: Int = 100
    ) -> Match? {
        let text = text.lowercased()
        let textLength = text.count

        // Exact match fast path
        if pattern.text == text {
            return Match(score: 0)
        }

        let location = 0
        var threshold = threshold

        // Seed with exact substring positions (speed up).
        var matchMask = [Int](repeating: 0, count: textLength)
        var bestLocation: Int? = findFirstExactIndex(pattern.text, in: text, from: location)

        var index = findIndex(of: pattern.text, in: text, from: bestLocation)
        while let idx = index {
            let score = calculateScore(
                patternLength: pattern.length, errors: 0, matchLocation: idx,
                expectedLocation: location, distance: distance
            )
            threshold = min(threshold, score)
            bestLocation = idx + pattern.length
            for k in 0..<pattern.length where idx + k < textLength {
                matchMask[idx + k] = 1
            }
            index = findIndex(of: pattern.text, in: text, from: bestLocation)
        }

        bestLocation = nil
        var score = 1.0
        var binMax = pattern.length + textLength
        var lastBitArr = [Int]()

        for errorLevel in 0..<pattern.length {
            var binMin = 0
            var binMid = binMax

            while binMin < binMid {
                if calculateScore(
                    patternLength: pattern.length, errors: errorLevel,
                    matchLocation: location + binMid, expectedLocation: location,
                    distance: distance
                ) <= threshold {
                    binMin = binMid
                } else {
                    binMax = binMid
                }
                binMid = (binMax - binMin) / 2 + binMin
            }

            binMax = binMid
            let start = max(1, location - binMid + 1)
            let finish = min(location + binMid, textLength) + pattern.length

            var bitArr = [Int](repeating: 0, count: finish + 2)
            bitArr[finish + 1] = (1 << errorLevel) - 1

            guard start <= finish else { continue }

            let textChars = Array(text)
            for j in stride(from: finish, through: start, by: -1) {
                let currentLocation = j - 1

                let charMatch: Int = {
                    guard currentLocation < textLength else { return 0 }
                    return pattern.alphabet[textChars[currentLocation]] ?? 0
                }()

                if charMatch != 0 {
                    matchMask[currentLocation] = 1
                }

                // First pass: exact match
                bitArr[j] = ((bitArr[j + 1] << 1) | 1) & charMatch

                // Subsequent passes: fuzzy match
                if errorLevel > 0 {
                    bitArr[j] |= (((lastBitArr[j + 1] | lastBitArr[j]) << 1) | 1) | lastBitArr[j + 1]
                }

                if (bitArr[j] & pattern.mask) != 0 {
                    score = calculateScore(
                        patternLength: pattern.length, errors: errorLevel,
                        matchLocation: currentLocation, expectedLocation: location,
                        distance: distance
                    )

                    if score <= threshold {
                        threshold = score
                        bestLocation = currentLocation
                        guard let best = bestLocation else { break }
                        if best > location {
                            // Binary search adjusts how far from expected location we stray
                        } else {
                            break
                        }
                    }
                }
            }

            // No hope at greater error levels
            if calculateScore(
                patternLength: pattern.length, errors: errorLevel + 1,
                matchLocation: location, expectedLocation: location,
                distance: distance
            ) > threshold {
                break
            }

            lastBitArr = bitArr
        }

        return score >= 1.0 ? nil : Match(score: score)
    }

    // MARK: - Internals

    private static func buildAlphabet(_ pattern: String) -> [Character: Int] {
        let length = pattern.count
        var mask = [Character: Int]()
        for (i, c) in pattern.enumerated() {
            mask[c] = (mask[c] ?? 0) | (1 << (length - i - 1))
        }
        return mask
    }

    private static func calculateScore(
        patternLength: Int,
        errors: Int,
        matchLocation: Int,
        expectedLocation: Int,
        distance: Int
    ) -> Double {
        let accuracy = Double(errors) / Double(patternLength)
        let proximity = abs(matchLocation - expectedLocation)
        if distance == 0 {
            return proximity != 0 ? 1 : accuracy
        }
        return accuracy + Double(proximity) / Double(distance)
    }

    private static func findFirstExactIndex(_ pattern: String, in text: String, from location: Int) -> Int? {
        guard let range = text.range(of: pattern, options: .literal,
                                     range: text.index(text.startIndex, offsetBy: min(location, text.count))..<text.endIndex)
        else { return nil }
        return text.distance(from: text.startIndex, to: range.lowerBound)
    }

    private static func findIndex(of pattern: String, in text: String, from position: Int?) -> Int? {
        guard let position, position < text.count else { return nil }
        let start = text.index(text.startIndex, offsetBy: position)
        guard let range = text.range(of: pattern, options: .literal, range: start..<text.endIndex) else { return nil }
        return text.distance(from: text.startIndex, to: range.lowerBound)
    }
}
