import Foundation

struct SentenceTranslationResult: Codable, Sendable {
    let translation: String
    let analysis: String?
}
