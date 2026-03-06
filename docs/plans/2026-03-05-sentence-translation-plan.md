# 短句和片段翻译功能 实施计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 让 SnapDict 智能区分单词/短句/中文输入，走不同翻译流水线，支持弹窗宽度自适应和独立句子本。

**Architecture:** 在现有单词翻译流程旁新增平行的短句翻译通道。InputClassifier 做类型检测，DeepSeekService 新增 translateSentence()，TranslationContentView 根据类型切换展示视图，PanelManager 动态调整弹窗宽度。句子本独立管理（SentenceEntry + SentenceBookManager）。

**Tech Stack:** Swift 6.0, SwiftUI, SwiftData, DeepSeek API

---

### Task 1: 创建 InputClassifier 输入类型检测

**Files:**
- Create: `SnapDict/Utilities/InputClassifier.swift`

**Step 1: 创建 InputClassifier**

```swift
// SnapDict/Utilities/InputClassifier.swift
import Foundation

enum InputType {
    case word       // 英文单词/短词组 → 走词典流水线
    case sentence   // 英文短句/片段 → 走翻译流水线
    case chinese    // 中文输入 → 中译英
}

enum InputClassifier {
    /// 判断输入文本的类型
    static func classify(_ text: String) -> InputType {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .word }

        // 包含中文字符 → 中译英
        if trimmed.unicodeScalars.contains(where: { isCJK($0) }) {
            return .chinese
        }

        // 纯英文：根据空格数和长度判断
        let wordCount = trimmed.split(separator: " ").count
        if wordCount <= 2 && trimmed.count <= 25 {
            return .word
        }

        return .sentence
    }

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        // CJK Unified Ideographs
        (0x4E00...0x9FFF).contains(scalar.value) ||
        // CJK Extension A
        (0x3400...0x4DBF).contains(scalar.value) ||
        // CJK Extension B
        (0x20000...0x2A6DF).contains(scalar.value) ||
        // CJK Compatibility Ideographs
        (0xF900...0xFAFF).contains(scalar.value)
    }
}
```

**Step 2: 运行 xcodegen 并构建验证**

```bash
cd /Users/zzp/Work/Workspace/Xcode/SnapDict
xcodegen generate
xcodebuild -project SnapDict.xcodeproj -scheme SnapDict build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

**Step 3: 提交**

```bash
git add SnapDict/Utilities/InputClassifier.swift
git commit -m "新增 InputClassifier 输入类型检测工具类"
```

---

### Task 2: 创建 SentenceTranslationResult 数据模型

**Files:**
- Create: `SnapDict/Models/SentenceTranslationResult.swift`

**Step 1: 创建模型**

```swift
// SnapDict/Models/SentenceTranslationResult.swift
import Foundation

struct SentenceTranslationResult: Codable, Sendable {
    let translation: String    // 译文
    let analysis: String?      // 语法/用法解析
}
```

**Step 2: 构建验证**

```bash
xcodegen generate
xcodebuild -project SnapDict.xcodeproj -scheme SnapDict build 2>&1 | tail -5
```

**Step 3: 提交**

```bash
git add SnapDict/Models/SentenceTranslationResult.swift
git commit -m "新增 SentenceTranslationResult 短句翻译结果模型"
```

---

### Task 3: 创建 SentenceEntry SwiftData 模型并注册

**Files:**
- Create: `SnapDict/Models/SentenceEntry.swift`
- Modify: `SnapDict/SnapDictApp.swift:33` — 在 ModelContainer 注册 SentenceEntry

**Step 1: 创建 SentenceEntry 模型**

```swift
// SnapDict/Models/SentenceEntry.swift
import Foundation
import SwiftData

@Model
final class SentenceEntry {
    @Attribute(.unique) var original: String
    var translation: String
    var analysis: String?
    var sourceLanguage: String   // "en" 或 "zh"
    var createdAt: Date

    init(original: String, translation: String, analysis: String? = nil, sourceLanguage: String, createdAt: Date = .now) {
        self.original = original
        self.translation = translation
        self.analysis = analysis
        self.sourceLanguage = sourceLanguage
        self.createdAt = createdAt
    }
}
```

**Step 2: 在 SnapDictApp.swift 注册 SentenceEntry**

修改 `SnapDictApp.swift:33`，将：

```swift
container = try ModelContainer(for: WordEntry.self, TranslationCache.self, TTSCache.self, configurations: config)
```

改为：

```swift
container = try ModelContainer(for: WordEntry.self, TranslationCache.self, TTSCache.self, SentenceEntry.self, configurations: config)
```

**Step 3: 构建验证**

```bash
xcodegen generate
xcodebuild -project SnapDict.xcodeproj -scheme SnapDict build 2>&1 | tail -5
```

**Step 4: 提交**

```bash
git add SnapDict/Models/SentenceEntry.swift SnapDict/SnapDictApp.swift
git commit -m "新增 SentenceEntry SwiftData 模型并注册到 ModelContainer"
```

---

### Task 4: DeepSeekService 新增 translateSentence 方法

**Files:**
- Modify: `SnapDict/Services/DeepSeekService.swift` — 在 `fetchMnemonic()` 方法前（约行 90）新增方法

**Step 1: 在 DeepSeekService 中添加 translateSentence 方法**

在 `translateWord()` 方法结束后（行 89 之后），`fetchMnemonic()` 方法开始前（行 91 之前），插入：

```swift
    /// 翻译短句或中文（不含助记和例句）
    func translateSentence(_ text: String, inputType: InputType, skipCache: Bool = false) async throws -> SentenceTranslationResult {
        let normalizedText = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let cacheKey = "s:" + normalizedText

        if !skipCache, let cached = CacheService.shared.getCachedSentenceTranslation(for: cacheKey) {
            return cached
        }

        let prompt: String
        switch inputType {
        case .sentence:
            prompt = """
            你是一个专业的英语翻译助手。请翻译以下英文短句/段落，只返回 JSON 格式：
            {"translation": "中文翻译（自然流畅）", "analysis": "简要语法/用法解析（2-3句话，点出关键语法点或地道用法）"}

            只返回 JSON，不要返回其他内容。

            输入：\(text)
            """
        case .chinese:
            prompt = """
            你是一个专业的英语翻译助手。请将以下中文翻译为英文，只返回 JSON 格式：
            {"translation": "英文翻译（自然地道）", "analysis": "简要用法说明（解释翻译选择或提供替代表达）"}

            只返回 JSON，不要返回其他内容。

            输入：\(text)
            """
        case .word:
            fatalError("translateSentence should not be called with .word type")
        }

        let cleaned = try await callAPI(prompt: prompt)

        guard let resultData = cleaned.data(using: .utf8) else {
            throw TranslationError.parseError
        }

        let result = try JSONDecoder().decode(SentenceTranslationResult.self, from: resultData)
        CacheService.shared.cacheSentenceTranslation(result, for: cacheKey)
        return result
    }
```

**Step 2: 构建验证**（此时会编译失败因为 CacheService 方法还不存在，跳到 Task 5）

---

### Task 5: CacheService 支持短句缓存

**Files:**
- Modify: `SnapDict/Services/CacheService.swift` — 在 `clearTranslationCache()` 方法前（约行 100）新增两个方法

**Step 1: 在 CacheService 中添加短句缓存读写方法**

在 `updateCachedExamples()` 方法结束后（行 99 之后），`clearTranslationCache()` 方法前（行 101 之前），插入：

```swift
    // MARK: - Sentence Translation Cache

    func getCachedSentenceTranslation(for key: String) -> SentenceTranslationResult? {
        return queue.sync {
            guard let container = modelContainer else { return nil }
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<TranslationCache>(
                predicate: #Predicate { $0.word == key }
            )
            guard let cached = try? context.fetch(descriptor).first,
                  let data = cached.jsonData.data(using: .utf8) else {
                return nil
            }
            return try? JSONDecoder().decode(SentenceTranslationResult.self, from: data)
        }
    }

    func cacheSentenceTranslation(_ result: SentenceTranslationResult, for key: String) {
        guard let jsonData = try? JSONEncoder().encode(result),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }

        queue.sync {
            guard let container = modelContainer else { return }
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<TranslationCache>(
                predicate: #Predicate { $0.word == key }
            )
            if let existing = try? context.fetch(descriptor).first {
                existing.jsonData = jsonString
                existing.createdAt = .now
            } else {
                context.insert(TranslationCache(word: key, jsonData: jsonString))
            }
            try? context.save()
        }
    }
```

注意：句子缓存 key 带有 `"s:"` 前缀（由 DeepSeekService 传入），与单词缓存自然分离。

**Step 2: 构建验证**（Task 4 + Task 5 一起）

```bash
xcodegen generate
xcodebuild -project SnapDict.xcodeproj -scheme SnapDict build 2>&1 | tail -5
```

**Step 3: 提交**

```bash
git add SnapDict/Services/DeepSeekService.swift SnapDict/Services/CacheService.swift
git commit -m "DeepSeekService 新增 translateSentence 方法及缓存支持"
```

---

### Task 6: 创建 SentenceBookManager

**Files:**
- Create: `SnapDict/Managers/SentenceBookManager.swift`
- Modify: `SnapDict/SnapDictApp.swift:40` — 初始化 SentenceBookManager

**Step 1: 创建 SentenceBookManager**

```swift
// SnapDict/Managers/SentenceBookManager.swift
import Foundation
import SwiftData

@MainActor
@Observable
final class SentenceBookManager {
    static let shared = SentenceBookManager()

    var modelContainer: ModelContainer?

    private init() {}

    func setup(container: ModelContainer) {
        self.modelContainer = container
    }

    @discardableResult
    func saveSentence(original: String, translation: String, analysis: String?, sourceLanguage: String) throws -> SentenceEntry {
        guard let container = modelContainer else {
            throw WordBookError.noContainer
        }
        let context = container.mainContext

        let descriptor = FetchDescriptor<SentenceEntry>(
            predicate: #Predicate { $0.original == original }
        )
        if let existing = try context.fetch(descriptor).first {
            existing.translation = translation
            existing.analysis = analysis
            try context.save()
            return existing
        }

        let entry = SentenceEntry(
            original: original,
            translation: translation,
            analysis: analysis,
            sourceLanguage: sourceLanguage
        )
        context.insert(entry)
        try context.save()
        return entry
    }

    func deleteSentence(_ entry: SentenceEntry) throws {
        guard let container = modelContainer else { return }
        let context = container.mainContext
        context.delete(entry)
        try context.save()
    }

    func deleteSentence(byOriginal original: String) throws {
        guard let container = modelContainer else { return }
        let context = container.mainContext
        let descriptor = FetchDescriptor<SentenceEntry>(
            predicate: #Predicate { $0.original == original }
        )
        if let entry = try context.fetch(descriptor).first {
            context.delete(entry)
            try context.save()
        }
    }

    func isSentenceSaved(_ original: String) -> Bool {
        guard let container = modelContainer else { return false }
        let context = container.mainContext
        let descriptor = FetchDescriptor<SentenceEntry>(
            predicate: #Predicate { $0.original == original }
        )
        return (try? context.fetchCount(descriptor)) ?? 0 > 0
    }

    func sentenceCount() -> Int {
        guard let container = modelContainer else { return 0 }
        let context = container.mainContext
        let descriptor = FetchDescriptor<SentenceEntry>()
        return (try? context.fetchCount(descriptor)) ?? 0
    }
}
```

**Step 2: 在 SnapDictApp.swift 初始化 SentenceBookManager**

在 `SnapDictApp.swift:40`（`CacheService.shared.setup(container: container)` 之后），添加：

```swift
        SentenceBookManager.shared.setup(container: container)
```

**Step 3: 构建验证**

```bash
xcodegen generate
xcodebuild -project SnapDict.xcodeproj -scheme SnapDict build 2>&1 | tail -5
```

**Step 4: 提交**

```bash
git add SnapDict/Managers/SentenceBookManager.swift SnapDict/SnapDictApp.swift
git commit -m "新增 SentenceBookManager 句子本管理器"
```

---

### Task 7: 创建 SentenceTranslationView 短句结果视图

**Files:**
- Create: `SnapDict/Views/SentenceTranslationView.swift`

**Step 1: 创建短句翻译结果视图**

```swift
// SnapDict/Views/SentenceTranslationView.swift
import SwiftUI

struct SentenceTranslationView: View {
    let originalText: String
    let result: SentenceTranslationResult
    let inputType: InputType
    let isSaved: Bool
    let onToggleSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 原文（灰色小字）
            Text(originalText)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(3)

            // 译文（主文字）
            Text(result.translation)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.primary)
                .textSelection(.enabled)

            // 语法/用法解析
            if let analysis = result.analysis, !analysis.isEmpty {
                Divider()
                    .padding(.vertical, 2)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "text.book.closed")
                            .font(.system(size: 12))
                        Text(inputType == .chinese ? "用法说明" : "语法解析")
                            .font(.system(size: 13))
                    }
                    .foregroundStyle(.secondary)

                    Text(analysis)
                        .font(.system(size: 14))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                }
            }

            Divider()
                .padding(.vertical, 2)

            // 操作栏
            HStack(spacing: 12) {
                // 收藏按钮
                Button {
                    onToggleSave()
                } label: {
                    Label(
                        isSaved ? "已收藏" : "收藏",
                        systemImage: isSaved ? "bookmark.fill" : "bookmark"
                    )
                    .font(.system(size: 13))
                    .foregroundStyle(isSaved ? .orange : .secondary)
                }
                .buttonStyle(.plain)

                // 复制译文按钮
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result.translation, forType: .string)
                } label: {
                    Label("复制译文", systemImage: "doc.on.doc")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
    }
}
```

**Step 2: 构建验证**

```bash
xcodegen generate
xcodebuild -project SnapDict.xcodeproj -scheme SnapDict build 2>&1 | tail -5
```

**Step 3: 提交**

```bash
git add SnapDict/Views/SentenceTranslationView.swift
git commit -m "新增 SentenceTranslationView 短句翻译结果视图"
```

---

### Task 8: TranslationContentView 集成输入类型分流

这是核心集成任务，修改 TranslationContentView 支持三种输入类型。

**Files:**
- Modify: `SnapDict/Views/TranslationContentView.swift`

**Step 1: 添加新的 State 属性**

在 `TranslationContentView.swift` 现有 `@State` 属性区域（约行 17-32）之后添加：

```swift
    @State private var sentenceResult: SentenceTranslationResult?
    @State private var currentInputType: InputType = .word
    @State private var isSentenceSaved = false
```

**Step 2: 修改 hasContent 判断**

将 `TranslationContentView.swift:41-43` 的 `hasContent` 改为：

```swift
    private var hasContent: Bool {
        isLoading || errorMessage != nil || result != nil || sentenceResult != nil
    }
```

**Step 3: 修改内容区域展示逻辑**

在 `TranslationContentView.swift:127`（`} else if let result {` 那行），将原来的：

```swift
                        } else if let result {
                            resultView(result)
                        }
```

改为：

```swift
                        } else if currentInputType == .word, let result {
                            resultView(result)
                        } else if let sentenceResult {
                            SentenceTranslationView(
                                originalText: query,
                                result: sentenceResult,
                                inputType: currentInputType,
                                isSaved: isSentenceSaved,
                                onToggleSave: { toggleSaveSentence() }
                            )
                        }
```

**Step 4: 修改 performTranslation 方法**

将 `TranslationContentView.swift:418-490` 的 `performTranslation` 方法替换为：

```swift
    private func performTranslation(forceNoAutoCorrect: Bool = false) {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let inputType = InputClassifier.classify(text)
        currentInputType = inputType

        correctionDismissed = false
        isLoading = true
        errorMessage = nil
        result = nil
        sentenceResult = nil
        isSaved = false
        isSentenceSaved = false
        isMnemonicLoading = false
        isExamplesLoading = false
        mnemonicError = nil
        examplesError = nil
        mnemonicTask?.cancel()
        examplesTask?.cancel()

        // 通知宽度变化
        PanelManager.shared.updatePanelWidth(for: inputType)

        translationTask = Task {
            switch inputType {
            case .word:
                // 原有单词翻译流程
                do {
                    let translationResult = try await DeepSeekService.shared.translateWord(text, forceNoAutoCorrect: forceNoAutoCorrect)
                    guard !Task.isCancelled else { return }
                    self.result = translationResult
                    self.isLoading = false
                    self.isSaved = WordBookManager.shared.isWordSaved(translationResult.word)

                    // 阶段 2：并行获取助记和例句
                    let correctedWord = translationResult.word
                    let translation = translationResult.translation

                    let enableMnemonic = UserDefaults.standard.object(forKey: Constants.UserDefaultsKey.enableMnemonic) as? Bool
                        ?? Constants.Defaults.enableMnemonic
                    let showExamples = UserDefaults.standard.object(forKey: Constants.UserDefaultsKey.showExamples) as? Bool
                        ?? Constants.Defaults.showExamples

                    if enableMnemonic {
                        mnemonicTask = Task {
                            isMnemonicLoading = true
                            mnemonicError = nil
                            do {
                                let mnemonic = try await DeepSeekService.shared.fetchMnemonic(correctedWord)
                                guard !Task.isCancelled else { return }
                                self.result?.etymology = mnemonic.etymology
                                self.result?.association = mnemonic.association
                            } catch {
                                guard !Task.isCancelled else { return }
                                self.mnemonicError = error.localizedDescription
                            }
                            self.isMnemonicLoading = false
                        }
                    }

                    if showExamples {
                        examplesTask = Task {
                            isExamplesLoading = true
                            examplesError = nil
                            do {
                                let examples = try await DeepSeekService.shared.fetchExamples(correctedWord, translation: translation)
                                guard !Task.isCancelled else { return }
                                self.result?.examples = examples
                            } catch {
                                guard !Task.isCancelled else { return }
                                self.examplesError = error.localizedDescription
                            }
                            self.isExamplesLoading = false
                        }
                    }
                } catch {
                    guard !Task.isCancelled else { return }
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }

            case .sentence, .chinese:
                // 短句/中文翻译流程
                do {
                    let sentenceResult = try await DeepSeekService.shared.translateSentence(text, inputType: inputType)
                    guard !Task.isCancelled else { return }
                    self.sentenceResult = sentenceResult
                    self.isLoading = false
                    self.isSentenceSaved = SentenceBookManager.shared.isSentenceSaved(text)
                } catch {
                    guard !Task.isCancelled else { return }
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
```

**Step 5: 修改 resetState 方法**

在 `TranslationContentView.swift:518-533` 的 `resetState()` 方法中，在 `result = nil` 之后添加：

```swift
        sentenceResult = nil
        currentInputType = .word
        isSentenceSaved = false
```

同时在 resetState 中增加宽度重置：

```swift
        PanelManager.shared.updatePanelWidth(for: .word)
```

**Step 6: 修改 debounceAutoTranslate 方法**

在 `TranslationContentView.swift:492-516` 的 `debounceAutoTranslate` 方法中，在清理状态部分（约行 504）的 `result = nil` 后面添加：

```swift
            sentenceResult = nil
```

**Step 7: 添加 toggleSaveSentence 方法**

在 `toggleSaveWord` 方法后面添加：

```swift
    private func toggleSaveSentence() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let sentenceResult else { return }
        do {
            if isSentenceSaved {
                try SentenceBookManager.shared.deleteSentence(byOriginal: text)
                isSentenceSaved = false
            } else {
                let sourceLanguage = currentInputType == .chinese ? "zh" : "en"
                try SentenceBookManager.shared.saveSentence(
                    original: text,
                    translation: sentenceResult.translation,
                    analysis: sentenceResult.analysis,
                    sourceLanguage: sourceLanguage
                )
                isSentenceSaved = true
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
```

**Step 8: 修改搜索框 placeholder 文字**

将 `TranslationContentView.swift:73` 的：

```swift
                TextField("输入单词或短语...", text: $query)
```

改为：

```swift
                TextField("输入单词、短句或中文...", text: $query)
```

**Step 9: 构建验证**（此时 PanelManager.updatePanelWidth 还不存在，先跳到 Task 9）

---

### Task 9: PanelManager 弹窗宽度自适应

**Files:**
- Modify: `SnapDict/Managers/PanelManager.swift`
- Modify: `SnapDict/Views/TranslationContentView.swift:140` — 移除硬编码宽度

**Step 1: PanelManager 添加宽度管理**

在 `PanelManager.swift:10`，将固定宽度改为可变：

```swift
    private var panelWidth: CGFloat = 420
    private let wordPanelWidth: CGFloat = 420
    private let sentencePanelWidth: CGFloat = 500
```

添加公开方法（在 `updateTranslationContentHeight` 方法附近，约行 187）：

```swift
    func updatePanelWidth(for inputType: InputType) {
        let targetWidth = (inputType == .word) ? wordPanelWidth : sentencePanelWidth
        guard panelWidth != targetWidth else { return }
        panelWidth = targetWidth

        guard let panel else { return }
        var frame = panel.frame
        let oldWidth = frame.size.width
        frame.size.width = targetWidth
        // 保持窗口中心 X 不变
        frame.origin.x -= (targetWidth - oldWidth) / 2

        // 更新 min/max size
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 1000
        panel.minSize = NSSize(width: targetWidth, height: compactHeight)
        panel.maxSize = NSSize(width: targetWidth, height: screenHeight)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        }
    }
```

**Step 2: 移除 TranslationContentView 中的硬编码宽度**

将 `TranslationContentView.swift:140` 的：

```swift
        .frame(width: 420)
```

改为：

```swift
        .frame(maxWidth: .infinity)
```

这样视图宽度跟随面板宽度自动调整。

**Step 3: 构建验证**（Task 8 + Task 9 一起）

```bash
xcodegen generate
xcodebuild -project SnapDict.xcodeproj -scheme SnapDict build 2>&1 | tail -5
```

**Step 4: 提交**

```bash
git add SnapDict/Views/TranslationContentView.swift SnapDict/Managers/PanelManager.swift
git commit -m "TranslationContentView 集成输入类型分流及弹窗宽度自适应"
```

---

### Task 10: 创建 PanelSentenceBookView 句子本视图

**Files:**
- Create: `SnapDict/Views/PanelSentenceBookView.swift`

**Step 1: 创建句子本列表视图**

```swift
// SnapDict/Views/PanelSentenceBookView.swift
import SwiftUI
import SwiftData

struct PanelSentenceBookView: View {
    @Query(sort: \SentenceEntry.createdAt, order: .reverse) private var sentences: [SentenceEntry]
    @State private var searchText = ""
    @State private var selectedEntry: SentenceEntry?

    private var filteredSentences: [SentenceEntry] {
        guard !searchText.isEmpty else { return sentences }
        let query = searchText.lowercased()
        return sentences.filter {
            $0.original.lowercased().contains(query) ||
            $0.translation.lowercased().contains(query)
        }
    }

    var body: some View {
        let currentSentences = filteredSentences
        VStack(spacing: 0) {
            // 工具栏
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.tertiary)
                        .font(.system(size: 13))
                    TextField("搜索...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

                Spacer()

                Text("\(sentences.count) 条")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if currentSentences.isEmpty {
                ContentUnavailableView {
                    Label(
                        searchText.isEmpty ? "暂无收藏句子" : "未找到匹配结果",
                        systemImage: searchText.isEmpty ? "text.quote" : "magnifyingglass"
                    )
                } description: {
                    Text(searchText.isEmpty ? "翻译短句时点击收藏按钮保存" : "试试其他关键词")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(currentSentences) { entry in
                            CompactSentenceRow(
                                entry: entry,
                                isSelected: selectedEntry?.id == entry.id,
                                onTap: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                        if selectedEntry?.id == entry.id {
                                            selectedEntry = nil
                                        } else {
                                            selectedEntry = entry
                                        }
                                    }
                                },
                                onDelete: {
                                    if selectedEntry?.id == entry.id { selectedEntry = nil }
                                    try? SentenceBookManager.shared.deleteSentence(entry)
                                }
                            )
                        }
                    }
                    .padding(10)
                }
            }
        }
    }
}

// MARK: - CompactSentenceRow

private struct CompactSentenceRow: View {
    let entry: SentenceEntry
    let isSelected: Bool
    let onTap: () -> Void
    let onDelete: () -> Void

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 主行
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.original)
                        .font(.system(size: 14))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(entry.translation)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                HStack(spacing: 4) {
                    Text(entry.sourceLanguage == "zh" ? "中→英" : "英→中")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())

                    Image(systemName: isSelected ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                        .foregroundStyle(.quaternary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)

            // 展开详情
            if isSelected {
                Divider().padding(.horizontal, 12)

                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.original)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)

                    Text(entry.translation)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)

                    if let analysis = entry.analysis, !analysis.isEmpty {
                        Divider()
                        Text(analysis)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)

                Divider().padding(.horizontal, 12)

                HStack {
                    Text(Self.dateFormatter.string(from: entry.createdAt))
                        .font(.system(size: 11))
                        .foregroundStyle(.quaternary)

                    Spacer()

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(entry.translation, forType: .string)
                    } label: {
                        Label("复制译文", systemImage: "doc.on.doc")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13))
                            .foregroundStyle(.red.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .background(
            isSelected
                ? AnyShapeStyle(Color.accentColor.opacity(0.06))
                : AnyShapeStyle(Color.primary.opacity(0.04)),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isSelected ? Color.accentColor.opacity(0.5) : Color.clear,
                    lineWidth: 1
                )
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}
```

**Step 2: 构建验证**

```bash
xcodegen generate
xcodebuild -project SnapDict.xcodeproj -scheme SnapDict build 2>&1 | tail -5
```

**Step 3: 提交**

```bash
git add SnapDict/Views/PanelSentenceBookView.swift
git commit -m "新增 PanelSentenceBookView 句子本列表视图"
```

---

### Task 11: PanelWordBookView 添加单词/句子分段切换

**Files:**
- Modify: `SnapDict/Views/PanelWordBookView.swift`

**Step 1: 添加分段选择器**

在 `PanelWordBookView.swift` 中：

1. 在现有 `@State` 属性区域（约行 6-9）添加：

```swift
    @State private var bookSegment: BookSegment = .words

    enum BookSegment: String, CaseIterable {
        case words = "单词"
        case sentences = "句子"
    }
```

2. 修改 `body` 属性，在 `VStack(spacing: 0)` 的最开始（`compactToolbar` 之前）加入 Picker：

```swift
            // 分段切换
            Picker("", selection: $bookSegment) {
                ForEach(BookSegment.allCases, id: \.self) { segment in
                    Text(segment.rawValue).tag(segment)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)
```

3. 将现有的 `compactToolbar` 和内容区域包裹在 `if bookSegment == .words` 中，然后在 `else` 分支展示 `PanelSentenceBookView()`：

将原有 body 内容改为：

```swift
    var body: some View {
        VStack(spacing: 0) {
            // 分段切换
            Picker("", selection: $bookSegment) {
                ForEach(BookSegment.allCases, id: \.self) { segment in
                    Text(segment.rawValue).tag(segment)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)

            if bookSegment == .words {
                wordBookContent
            } else {
                PanelSentenceBookView()
            }
        }
    }

    @ViewBuilder
    private var wordBookContent: some View {
        let currentWords = filteredWords
        // ... 原有的 compactToolbar + 内容区代码（从 compactToolbar 到闭合大括号）
        compactToolbar

        Divider()

        if currentWords.isEmpty {
            ContentUnavailableView {
                // ... 保持原有代码
            }
        } else {
            ScrollView {
                // ... 保持原有代码
            }
        }
    }
```

具体做法：将 `body` 中 `VStack` 内的 `compactToolbar` 到 `}` 之间的所有内容抽取到新的 `wordBookContent` 计算属性中。

**Step 2: 构建验证**

```bash
xcodegen generate
xcodebuild -project SnapDict.xcodeproj -scheme SnapDict build 2>&1 | tail -5
```

**Step 3: 提交**

```bash
git add SnapDict/Views/PanelWordBookView.swift
git commit -m "单词本添加单词/句子分段切换"
```

---

### Task 12: 最终集成验证与修复

**Step 1: 全量构建**

```bash
cd /Users/zzp/Work/Workspace/Xcode/SnapDict
xcodegen generate
xcodebuild -project SnapDict.xcodeproj -scheme SnapDict build 2>&1 | tail -20
```

**Step 2: 修复编译错误**

处理可能出现的编译错误：
- Swift 6 并发安全警告（`Sendable` 约束）
- 缺少的导入
- 类型不匹配

**Step 3: 运行 APP 手动验证**

打开 Xcode 运行 APP，验证以下场景：
1. 输入英文单词 "hello" → 走词典流水线，显示音标+释义+助记+例句
2. 输入英文短句 "I want to learn Swift" → 走短句翻译，显示译文+语法解析
3. 输入中文 "我想学编程" → 中译英，显示英文译文+用法说明
4. 短句模式下弹窗自动加宽
5. 短句翻译结果可收藏到句子本
6. 单词本 Tab 可切换查看单词/句子

**Step 4: 提交最终修复**

```bash
git add -A
git commit -m "短句和片段翻译功能集成完成"
```
