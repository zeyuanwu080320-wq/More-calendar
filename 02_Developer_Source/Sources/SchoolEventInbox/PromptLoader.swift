import Foundation

enum PromptLoader {
    enum LoadError: LocalizedError {
        case missing

        var errorDescription: String? {
            "缺少 system_prompt.txt"
        }
    }

    static func load() throws -> String {
        #if SWIFT_PACKAGE
        if let url = Bundle.module.url(forResource: "system_prompt", withExtension: "txt"),
           let text = try? String(contentsOf: url, encoding: .utf8),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }
        #endif
        if let url = Bundle.main.url(forResource: "system_prompt", withExtension: "txt"),
           let text = try? String(contentsOf: url, encoding: .utf8),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }
        throw LoadError.missing
    }
}
