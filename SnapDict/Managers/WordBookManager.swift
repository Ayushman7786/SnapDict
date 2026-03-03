import Foundation
import SwiftData

@MainActor
@Observable
final class WordBookManager {
    static let shared = WordBookManager()

    var modelContainer: ModelContainer?

    private init() {}

    func setup(container: ModelContainer) {
        self.modelContainer = container
    }

    @discardableResult
    func saveWord(from result: TranslationResult) throws -> WordEntry {
        guard let container = modelContainer else {
            throw WordBookError.noContainer
        }
        let context = container.mainContext

        let descriptor = FetchDescriptor<WordEntry>(
            predicate: #Predicate { $0.word == result.word }
        )
        if let existing = try context.fetch(descriptor).first {
            existing.phonetic = result.phonetic
            existing.translation = result.translation
            existing.examples = result.examples
            try context.save()
            return existing
        }

        let entry = WordEntry(
            word: result.word,
            phonetic: result.phonetic,
            translation: result.translation,
            examples: result.examples
        )
        context.insert(entry)
        try context.save()
        return entry
    }

    func deleteWord(_ entry: WordEntry) throws {
        guard let container = modelContainer else { return }
        let context = container.mainContext
        context.delete(entry)
        try context.save()
    }

    func deleteWord(byName word: String) throws {
        guard let container = modelContainer else { return }
        let context = container.mainContext
        let descriptor = FetchDescriptor<WordEntry>(
            predicate: #Predicate { $0.word == word }
        )
        if let entry = try context.fetch(descriptor).first {
            context.delete(entry)
            try context.save()
        }
    }

    func toggleMastered(_ entry: WordEntry) throws {
        guard let container = modelContainer else { return }
        let context = container.mainContext
        entry.isMastered.toggle()
        try context.save()
    }

    func isWordSaved(_ word: String) -> Bool {
        guard let container = modelContainer else { return false }
        let context = container.mainContext
        let descriptor = FetchDescriptor<WordEntry>(
            predicate: #Predicate { $0.word == word }
        )
        return (try? context.fetchCount(descriptor)) ?? 0 > 0
    }

    func wordCount() -> Int {
        guard let container = modelContainer else { return 0 }
        let context = container.mainContext
        let descriptor = FetchDescriptor<WordEntry>()
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    func nextWordForPush() -> WordEntry? {
        guard let container = modelContainer else { return nil }
        let context = container.mainContext
        let pushOnlyLearning = UserDefaults.standard.object(forKey: Constants.UserDefaultsKey.pushOnlyLearning) as? Bool
            ?? Constants.Defaults.pushOnlyLearning
        let randomModeRaw = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.pushRandomMode)
        let randomMode = randomModeRaw.flatMap { Constants.PushRandomMode(rawValue: $0) } ?? Constants.Defaults.pushRandomMode

        switch randomMode {
        case .allWords:
            // 完全随机：从所有候选单词中随机选取，忽略推送次数
            var descriptor: FetchDescriptor<WordEntry>
            if pushOnlyLearning {
                descriptor = FetchDescriptor<WordEntry>(predicate: #Predicate { !$0.isMastered })
            } else {
                descriptor = FetchDescriptor<WordEntry>()
            }
            guard let candidates = try? context.fetch(descriptor), !candidates.isEmpty else { return nil }
            return candidates.randomElement()

        case .minCount:
            // 加权随机：权重 = 1 / (pushCount + 1)，低频单词概率更高，但高频单词也有机会被选到
            var descriptor: FetchDescriptor<WordEntry>
            if pushOnlyLearning {
                descriptor = FetchDescriptor<WordEntry>(predicate: #Predicate { !$0.isMastered })
            } else {
                descriptor = FetchDescriptor<WordEntry>()
            }
            guard let candidates = try? context.fetch(descriptor), !candidates.isEmpty else { return nil }

            let weights = candidates.map { 1.0 / Double($0.pushCount + 1) }
            let totalWeight = weights.reduce(0, +)
            var pick = Double.random(in: 0..<totalWeight)
            for (entry, weight) in zip(candidates, weights) {
                pick -= weight
                if pick <= 0 { return entry }
            }
            return candidates.last
        }
    }

    func lastPushedWord() -> WordEntry? {
        guard let container = modelContainer else { return nil }
        let context = container.mainContext
        var descriptor = FetchDescriptor<WordEntry>(
            predicate: #Predicate { $0.lastPushedAt != nil },
            sortBy: [SortDescriptor(\.lastPushedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    func markPushed(_ entry: WordEntry) throws {
        guard let container = modelContainer else { return }
        let context = container.mainContext
        entry.lastPushedAt = .now
        entry.pushCount += 1
        try context.save()
    }
}

enum WordBookError: LocalizedError {
    case noContainer

    var errorDescription: String? {
        switch self {
        case .noContainer: "数据库未初始化"
        }
    }
}
