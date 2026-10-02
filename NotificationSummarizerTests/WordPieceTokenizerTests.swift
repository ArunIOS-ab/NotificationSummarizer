import XCTest
@testable import NotificationSummarizer

/// Covers the dependency-free WordPiece tokenizer that feeds the Core ML classifier.
final class WordPieceTokenizerTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokenizer-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
        directory = nil
    }

    private func makeVocab(_ lines: [String]) throws -> URL {
        let url = directory.appendingPathComponent("vocab.txt")
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func makeTokenizer(maxLength: Int = 8) throws -> WordPieceTokenizer {
        let url = try makeVocab([
            "[PAD]", "[UNK]", "[CLS]", "[SEP]",
            "hello", "world", "!",
            "play", "##ing", "##s", "un", "##break",
        ])
        return try XCTUnwrap(WordPieceTokenizer(vocabURL: url, maxLength: maxLength))
    }

    // MARK: - Loading

    func testInitialiserFailsWhenSpecialTokensAreMissing() throws {
        let url = try makeVocab(["[PAD]", "hello"])
        XCTAssertNil(WordPieceTokenizer(vocabURL: url))
    }

    func testInitialiserFailsForMissingFile() {
        let url = directory.appendingPathComponent("does-not-exist.txt")
        XCTAssertNil(WordPieceTokenizer(vocabURL: url))
    }

    func testVocabularyIsIndexedByLineOrder() throws {
        let tokenizer = try makeTokenizer()
        // "hello" is index 4, so the encoded body must contain 4 after [CLS] (index 2).
        let ids = tokenizer.encode("hello").ids
        XCTAssertEqual(ids[0], 2)
        XCTAssertEqual(ids[1], 4)
    }

    // MARK: - Encoding

    func testEncodesWordsAndPunctuation() throws {
        let tokenizer = try makeTokenizer()
        let (ids, mask) = tokenizer.encode("Hello world!")

        XCTAssertEqual(Array(ids), [2, 4, 5, 6, 3, 0, 0, 0])
        XCTAssertEqual(Array(mask), [1, 1, 1, 1, 1, 0, 0, 0])
    }

    func testLowercasesInput() throws {
        let tokenizer = try makeTokenizer()
        XCTAssertEqual(tokenizer.encode("HELLO").ids, tokenizer.encode("hello").ids)
    }

    func testCollapsesRunsOfWhitespace() throws {
        let tokenizer = try makeTokenizer()
        XCTAssertEqual(tokenizer.encode("hello \n\t world").ids, tokenizer.encode("hello world").ids)
    }

    func testSplitsUnknownWordIntoSubwordPieces() throws {
        let tokenizer = try makeTokenizer()
        let ids = tokenizer.encode("plays").ids
        // "play" (7) + "##s" (9), wrapped in [CLS]/[SEP].
        XCTAssertEqual(Array(ids.prefix(4)), [2, 7, 9, 3])
    }

    func testUnknownWordFallsBackToUNKToken() throws {
        let tokenizer = try makeTokenizer()
        let ids = tokenizer.encode("zzz").ids
        XCTAssertEqual(ids[1], 1, "an unsegmentable word must map to [UNK]")
    }

    func testAlwaysPadsToMaxLengthAndMarksPaddingWithZeroMask() throws {
        let tokenizer = try makeTokenizer(maxLength: 16)
        let (ids, mask) = tokenizer.encode("hello")

        XCTAssertEqual(ids.count, 16)
        XCTAssertEqual(mask.count, 16)
        XCTAssertEqual(mask.reduce(0, +), 3, "[CLS] hello [SEP] = 3 real tokens")
        XCTAssertEqual(Array(ids.suffix(12)), Array(repeating: 0, count: 12))
    }

    func testTruncatesLongInputToMaxLength() throws {
        let tokenizer = try makeTokenizer(maxLength: 6)
        let (ids, mask) = tokenizer.encode("hello world! hello world! hello world!")

        XCTAssertEqual(ids.count, 6)
        XCTAssertEqual(mask.count, 6)
        XCTAssertEqual(ids.last, 3, "the sequence must still end with [SEP]")
    }

    func testMaxLengthOfTwoEmitsOnlySpecialTokens() throws {
        let tokenizer = try makeTokenizer(maxLength: 2)
        let (ids, mask) = tokenizer.encode("hello world")

        XCTAssertEqual(Array(ids), [2, 3])
        XCTAssertEqual(Array(mask), [1, 1])
    }

    func testEmptyInputStillProducesValidSequence() throws {
        let tokenizer = try makeTokenizer()
        let (ids, mask) = tokenizer.encode("   ")

        XCTAssertEqual(ids.first, 2)
        XCTAssertEqual(ids[1], 3)
        XCTAssertEqual(mask.reduce(0, +), 2)
    }
}
