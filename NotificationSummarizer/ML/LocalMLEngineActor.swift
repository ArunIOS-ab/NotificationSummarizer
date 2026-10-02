@preconcurrency import CoreML
import Foundation
import os

actor LocalMLEngineActor {
    static let shared = LocalMLEngineActor()

    private let logger = Logger(subsystem: "com.example.NotificationSummarizer", category: "LocalML")
    private let model: MLModel?
    private let tokenizer: WordPieceTokenizer?
    private let modelQueue = DispatchQueue(label: "NotificationSummarizer.CoreML", qos: .userInitiated)
    private let memoryPressureSource: DispatchSourceMemoryPressure?

    init() {
        let config = MLModelConfiguration()
        config.computeUnits = .all
        let modelURL = Bundle.main.url(forResource: "NotificationClassifier", withExtension: "mlmodelc")
            ?? Bundle.main.url(forResource: "NotificationClassifier", withExtension: "mlpackage")
        if let modelURL, let loaded = try? MLModel(contentsOf: modelURL, configuration: config) {
            self.model = loaded
        } else {
            self.model = nil
        }
        if let vocabURL = Bundle.main.url(forResource: "vocab", withExtension: "txt", subdirectory: "Tokenizer") {
            self.tokenizer = WordPieceTokenizer(vocabURL: vocabURL)
        } else {
            self.tokenizer = nil
        }

        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler {
            NotificationCenter.default.post(name: .notificationSummarizerMemoryPressure, object: nil)
        }
        source.resume()
        self.memoryPressureSource = source
    }

    func classify(text: String) async -> NotificationCategory {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .personal }
        do {
            return try await withTimeout(seconds: 1.5) { [self] in
                try await neuralClassify(text: text)
            }
        } catch {
            logger.debug("Neural classification fallback: \(String(describing: error), privacy: .public)")
            return RuleClassifier.category(for: text)
        }
    }

    func summarize(text: String) async throws -> String {
        do {
            return try await withTimeout(seconds: 1.5) {
                RuleSummarizer.summarize(text)
            }
        } catch {
            return RuleSummarizer.summarize(text)
        }
    }

    private func neuralClassify(text: String) async throws -> NotificationCategory {
        guard let model, let tokenizer else { throw LocalMLError.modelUnavailable }
        let encoded = tokenizer.encode(text)
        let ids = try makeArray(encoded.ids)
        let mask = try makeArray(encoded.mask)

        let provider = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": MLFeatureValue(multiArray: ids),
            "attention_mask": MLFeatureValue(multiArray: mask)
        ])

        let result: MLFeatureProvider = try await withCheckedThrowingContinuation { continuation in
            modelQueue.async {
                do { continuation.resume(returning: try model.prediction(from: provider)) }
                catch { continuation.resume(throwing: error) }
            }
        }

        if let label = result.featureValue(for: "classLabel")?.stringValue,
           let category = NotificationCategory(rawValue: label) {
            return category
        }
        throw LocalMLError.invalidOutput
    }

    private func makeArray(_ values: [Int32]) throws -> MLMultiArray {
        let array = try MLMultiArray(shape: [1, NSNumber(value: values.count)], dataType: .int32)
        for (index, value) in values.enumerated() {
            array[index] = NSNumber(value: value)
        }
        return array
    }

    private func withTimeout<T: Sendable>(seconds: Double, operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw LocalMLError.timeout
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }
}

enum LocalMLError: Error {
    case modelUnavailable
    case invalidOutput
    case timeout
    case memoryPressure
}

private enum RuleClassifier {
    static func category(for text: String) -> NotificationCategory {
        let s = text.lowercased()
        if contains(s, ["otp", "verification", "login", "signed in", "password", "security", "suspicious", "fraud"]) { return .security }
        if contains(s, ["charged", "debit", "credited", "upi", "payment", "transaction", "bank", "card", "refund", "salary", "invoice"]) { return .finance }
        if contains(s, ["sale", "offer", "discount", "coupon", "deal", "% off", "promo", "limited time"]) { return .promotional }
        if contains(s, ["meeting", "calendar", "deadline", "slack", "jira", "office", "work", "interview", "standup"]) { return .work }
        if contains(s, ["message", "commented", "liked", "followed", "instagram", "whatsapp", "telegram", "facebook"]) { return .social }
        return .personal
    }

    private static func contains(_ text: String, _ needles: [String]) -> Bool { needles.contains { text.contains($0) } }
}

private enum RuleSummarizer {
    static func summarize(_ text: String) -> String {
        let cleaned = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { return "No actionable notification details available." }

        if let match = firstMatch(in: cleaned, pattern: #"(?i)charged\s+\$([0-9,]+(?:\.[0-9]{2})?)\s+at\s+([A-Za-z0-9 &'’,-]+?)(?=\.|\s+Tap\b)"#) {
            let amount = match[1], merchant = match[2].trimmingCharacters(in: .whitespacesAndNewlines)
            let suffix = firstMatch(in: cleaned, pattern: #"(?i)(?:ending|ends? in)\s+(\d{4})"#)?[1]
            if let suffix { return "$\(amount) charge at \(merchant) on card ending in \(suffix)." }
            return "$\(amount) charge at \(merchant)."
        }

        let sentences = cleaned.split(whereSeparator: { ".!?".contains($0) }).map(String.init)
        let candidate = sentences.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? cleaned
        let words = candidate.split(separator: " ")
        let limited = words.prefix(20).joined(separator: " ")
        return limited + (words.count > 20 ? "…" : "")
    }

    private static func firstMatch(in text: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        return (0..<match.numberOfRanges).compactMap { index in
            let r = match.range(at: index)
            guard r.location != NSNotFound, let swiftRange = Range(r, in: text) else { return nil }
            return String(text[swiftRange])
        }
    }
}


extension Notification.Name {
    static let notificationSummarizerMemoryPressure = Notification.Name("NotificationSummarizerMemoryPressure")
}
