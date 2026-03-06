import Foundation

struct PartialWordResult: Sendable {
    var word: String?
    var phonetic: String?
    var translation: String?
    var originalInput: String?
    var etymology: String?
    var association: String?
    var examples: [String] = []
    var isComplete: Bool = false
    var notFound: Bool = false
    var suggestion: String?
}

struct PartialSentenceResult: Sendable {
    var translation: String?
    var analysis: String?
    var isComplete: Bool = false
}
