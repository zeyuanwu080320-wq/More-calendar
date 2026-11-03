import Foundation
import Vision

public enum OCRError: LocalizedError, Equatable, Sendable {
    case invalidImage
    case noText
    case recognitionFailed

    public var errorDescription: String? {
        switch self {
        case .invalidImage: return "图片无法读取"
        case .noText: return "图片中未识别到文字"
        case .recognitionFailed: return "本地 OCR 失败"
        }
    }
}

public struct OCRLine: Equatable, Sendable {
    public let text: String
    public let confidence: Float

    public init(text: String, confidence: Float) {
        self.text = text
        self.confidence = confidence
    }
}

public struct OCRResult: Equatable, Sendable {
    public let text: String
    public let lines: [OCRLine]

    public init(text: String, lines: [OCRLine]) {
        self.text = text
        self.lines = lines
    }
}

/// Pure local OCR. Only the resulting text is ever passed to the network layer.
public final class OCRService: @unchecked Sendable {
    public init() {}

    public func recognize(imageData: Data) async throws -> OCRResult {
        guard !imageData.isEmpty else { throw OCRError.invalidImage }

        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = false
        request.recognitionLanguages = [
            Locale.Language(identifier: "zh-Hans"),
            Locale.Language(identifier: "en-US")
        ]

        let observations: [RecognizedTextObservation]
        do {
            observations = try await request.perform(on: imageData, orientation: nil)
        } catch {
            throw OCRError.recognitionFailed
        }

        // Vision normalizes coordinates with the origin at the bottom-left.
        // Sort top-to-bottom, then left-to-right so the result reads naturally.
        let ordered: [RecognizedTextObservation] = observations.sorted { (lhs: RecognizedTextObservation, rhs: RecognizedTextObservation) in
            let lhsBox = lhs.boundingBox.cgRect
            let rhsBox = rhs.boundingBox.cgRect
            let yDifference = lhsBox.midY - rhsBox.midY
            if abs(yDifference) > 0.012 {
                return yDifference > 0
            }
            return lhsBox.minX < rhsBox.minX
        }

        let lines = ordered.compactMap { observation -> OCRLine? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return OCRLine(text: text, confidence: candidate.confidence)
        }

        guard !lines.isEmpty else { throw OCRError.noText }
        return OCRResult(text: lines.map { $0.text }.joined(separator: "\n"), lines: lines)
    }
}
