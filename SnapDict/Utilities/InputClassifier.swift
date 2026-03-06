import Foundation

enum InputType {
    case word       // 英文单词/短词组 → 走词典流水线
    case sentence   // 英文短句/片段 → 走翻译流水线
    case chinese    // 中文输入 → 中译英
}

enum InputClassifier {
    static func classify(_ text: String) -> InputType {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .word }

        if trimmed.unicodeScalars.contains(where: { isCJK($0) }) {
            return .chinese
        }

        let wordCount = trimmed.split(separator: " ").count
        if wordCount <= 2 && trimmed.count <= 25 {
            return .word
        }

        return .sentence
    }

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        (0x4E00...0x9FFF).contains(scalar.value) ||
        (0x3400...0x4DBF).contains(scalar.value) ||
        (0x20000...0x2A6DF).contains(scalar.value) ||
        (0xF900...0xFAFF).contains(scalar.value)
    }
}
