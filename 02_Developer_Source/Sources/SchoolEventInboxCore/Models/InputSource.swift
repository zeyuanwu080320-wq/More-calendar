import Foundation

/// Where the user's raw input comes from.
///
/// Lives in Core so the assembly rules can be unit-tested without a UI: the
/// text-sent-to-DeepSeek contract is the part most likely to break silently.
public enum InputSource: String, CaseIterable, Identifiable, Sendable {
    /// An email body plus optional screenshots OCR'd on-device.
    case email
    /// Free-form text pasted directly; never touches the OCR pipeline.
    case text

    public var id: String { rawValue }
}

/// Builds the payload handed to DeepSeek from the active input source.
///
/// The `text` source deliberately ignores `ocrSections`: "skip OCR" is enforced
/// structurally here rather than by an empty-array check at the call site, so a
/// future change to the image pipeline cannot silently reintroduce OCR work.
public enum InputComposer {
    /// One image's local OCR output, kept as a value so composing stays pure.
    public struct OCRSection: Equatable, Sendable {
        public let name: String
        public let text: String

        public init(name: String, text: String) {
            self.name = name
            self.text = text
        }
    }

    /// The exact text sent to the model. Section headers are part of the
    /// DeepSeek prompt contract and must not change format casually.
    public static func compose(
        source: InputSource,
        emailBody: String,
        plainText: String,
        ocrSections: [OCRSection]
    ) -> String {
        var parts: [String] = []
        switch source {
        case .email:
            let trimmed = emailBody.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                parts.append("【邮件正文】\n\(trimmed)")
            }
            for (index, section) in ocrSections.enumerated() {
                parts.append("【图片 \(index + 1) 本地 OCR：\(section.name)】\n\(section.text)")
            }
        case .text:
            let trimmed = plainText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                parts.append("【纯文本】\n\(trimmed)")
            }
        }
        return parts.joined(separator: "\n\n")
    }

    /// Whether the Parse button should be enabled.
    public static func hasInput(
        source: InputSource,
        emailBody: String,
        plainText: String,
        imageCount: Int
    ) -> Bool {
        switch source {
        case .email:
            return !emailBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || imageCount > 0
        case .text:
            return !plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// Value stored in the privacy log's `inputType`.
    ///
    /// Mixed email+images stays `"email"` so V1 log files keep the same meaning;
    /// `"text"` is the one new value V2.0 introduces.
    public static func logInputType(
        source: InputSource,
        emailBody: String,
        imageCount: Int
    ) -> String {
        if source == .text { return "text" }
        if imageCount > 0 {
            return emailBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "image" : "email"
        }
        return "email"
    }
}
