import Foundation

/// Small, dependency-free WordPiece tokenizer compatible with the basic DistilBERT tokenizer.
/// Add the model's `vocab.txt` to Resources/Tokenizer for neural classification.
struct WordPieceTokenizer: Sendable {
    private let vocabulary: [String: Int]
    private let unkID: Int
    private let clsID: Int
    private let sepID: Int
    private let padID: Int
    private let maxLength: Int

    init?(vocabURL: URL, maxLength: Int = 256) {
        guard let text = try? String(contentsOf: vocabURL, encoding: .utf8) else { return nil }
        var vocab: [String: Int] = [:]
        for (index, token) in text.split(whereSeparator: \.isNewline).enumerated() {
            vocab[String(token)] = index
        }
        guard let unk = vocab["[UNK]"], let cls = vocab["[CLS]"],
              let sep = vocab["[SEP]"], let pad = vocab["[PAD]"] else { return nil }
        vocabulary = vocab
        unkID = unk; clsID = cls; sepID = sep; padID = pad; self.maxLength = maxLength
    }

    func encode(_ text: String) -> (ids: [Int32], mask: [Int32]) {
        let normalized = text.lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let words = basicTokenize(normalized)
        var ids: [Int32] = [Int32(clsID)]
        let room = max(0, maxLength - 2)
        for word in words {
            for id in wordPiece(word) {
                if ids.count >= room + 1 {
                    break
                }
                ids.append(Int32(id))
            }
            if ids.count >= room + 1 {
                break
            }
        }
        ids.append(Int32(sepID))
        ids = Array(ids.prefix(maxLength))
        let realCount = ids.count
        if ids.count < maxLength {
            ids += Array(repeating: Int32(padID), count: maxLength - ids.count)
        }
        let mask = Array(repeating: Int32(1), count: realCount) + Array(repeating: Int32(0), count: maxLength - realCount)
        return (ids, mask)
    }

    private func basicTokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        for scalar in text.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                if !current.isEmpty {
                    tokens.append(current); current = ""
                }
            } else if CharacterSet.punctuationCharacters.contains(scalar) {
                if !current.isEmpty {
                    tokens.append(current); current = ""
                }
                tokens.append(String(scalar))
            } else {
                current.append(String(scalar))
            }
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }

    private func wordPiece(_ word: String) -> [Int] {
        if let id = vocabulary[word] {
            return [id]
        }
        let chars = Array(word)
        var start = 0
        var output: [Int] = []
        while start < chars.count {
            var end = chars.count
            var found: Int?
            while start < end {
                var piece = String(chars[start ..< end])
                if start > 0 {
                    piece = "##" + piece
                }
                if let id = vocabulary[piece] {
                    found = id; break
                }
                end -= 1
            }
            guard let id = found else { return [unkID] }
            output.append(id)
            start = end
        }
        return output
    }
}
