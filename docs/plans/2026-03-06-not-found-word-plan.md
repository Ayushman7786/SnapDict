# 错误拼写词"未找到"空状态 实施计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 用户点击"仍查询"后，若词不存在则显示空状态 + 纠正建议按钮，而非牵强的翻译结果。

**Architecture:** 在 forceNoAutoCorrect 模式的 prompt 中增加 `not_found` / `suggestion` 字段，流式解析后前端根据标记显示空状态视图。改动涉及 3 个文件：模型、服务、视图。

**Tech Stack:** Swift 6.0, SwiftUI, DeepSeek SSE API, PartialJSON

---

### Task 1: 数据模型 — PartialWordResult 增加 notFound 和 suggestion 字段

**Files:**
- Modify: `SnapDict/Models/PartialResult.swift:3-12`

**Step 1: 添加字段**

在 `PartialWordResult` 中添加两个字段：

```swift
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
```

**Step 2: 构建验证**

Run: `xcodebuild -project SnapDict.xcodeproj -scheme SnapDict build 2>&1 | tail -3`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add SnapDict/Models/PartialResult.swift
git commit -m "PartialWordResult 增加 notFound 和 suggestion 字段"
```

---

### Task 2: 服务层 — DeepSeekService prompt 和流式解析

**Files:**
- Modify: `SnapDict/Services/DeepSeekService.swift:65-90` (流式解析)
- Modify: `SnapDict/Services/DeepSeekService.swift:282-323` (prompt 构建)
- Modify: `SnapDict/Services/DeepSeekService.swift:93-111` (缓存逻辑)
- Modify: `SnapDict/Services/DeepSeekService.swift:506-514` (partialEqual)

**Step 1: 修改 buildWordPrompt — forceNoAutoCorrect 分支**

在 `buildWordPrompt` 方法中，`forceNoAutoCorrect == true` 的 else 分支改为：

```swift
} else {
    instructions += """
    不要返回 word 字段。不要自动纠正拼写。
    如果该词不是一个真实存在的英文单词，只返回 {"not_found": true, "suggestion": "你认为用户想查的正确单词"}，不要编造释义。
    如果是真实单词，按正常格式返回翻译结果。
    如果输入的是中文，则翻译为英文。
    """
}
```

**Step 2: 流式解析中检测 not_found 和 suggestion**

在 `translateWordStreaming` 的 for-await 循环中，解析 `corrected_word` 之后、解析 `phonetic` 之前，添加 not_found 检测：

```swift
// 检测 not_found（仅 forceNoAutoCorrect 模式）
if forceNoAutoCorrect {
    if let nf = dict["not_found"] as? Bool, nf {
        partial.notFound = true
        partial.suggestion = dict["suggestion"] as? String
        // not_found 时不解析其他翻译字段
        if !partialEqual(lastPartial, partial) {
            continuation.yield(partial)
            lastPartial = partial
        }
        continue
    }
}
```

位置：在第 76 行 `}` 之后（`forceNoAutoCorrect` 块结束后），第 78 行 `partial.phonetic = ...` 之前。

**Step 3: 缓存逻辑 — notFound 结果不缓存**

在流结束后的缓存逻辑处（约第 99-111 行），将缓存条件改为：

```swift
// 缓存完整结果（notFound 不缓存）
if let word = lastPartial.word, !word.isEmpty, !lastPartial.notFound {
    let fullResult = TranslationResult(...)
    CacheService.shared.cacheTranslation(fullResult)
}
```

**Step 4: partialEqual 增加 notFound 和 suggestion 比较**

```swift
private func partialEqual(_ a: PartialWordResult, _ b: PartialWordResult) -> Bool {
    a.word == b.word &&
    a.phonetic == b.phonetic &&
    a.translation == b.translation &&
    a.originalInput == b.originalInput &&
    a.etymology == b.etymology &&
    a.association == b.association &&
    a.examples == b.examples &&
    a.notFound == b.notFound &&
    a.suggestion == b.suggestion
}
```

**Step 5: 构建验证**

Run: `xcodebuild -project SnapDict.xcodeproj -scheme SnapDict build 2>&1 | tail -3`
Expected: BUILD SUCCEEDED

**Step 6: Commit**

```bash
git add SnapDict/Services/DeepSeekService.swift
git commit -m "DeepSeekService 支持 not_found 检测和建议词"
```

---

### Task 3: 视图层 — TranslationContentView 空状态显示

**Files:**
- Modify: `SnapDict/Views/TranslationContentView.swift`

**Step 1: 添加 notFoundView 方法**

在 `partialResultView` 方法附近添加新的空状态视图方法：

```swift
@ViewBuilder
private func notFoundView(_ partial: PartialWordResult) -> some View {
    HStack {
        Spacer()
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("未找到该词")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
            if let suggestion = partial.suggestion, !suggestion.isEmpty {
                Button {
                    query = suggestion
                    debounceTask?.cancel()
                    performTranslation()
                } label: {
                    Text("查询 \(suggestion)")
                        .font(.system(size: 13))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        Spacer()
    }
    .padding(.top, 40)
}
```

**Step 2: 在 partialResultView 开头检测 notFound**

在 `partialResultView` 方法最开头（`partialCorrectionBanner` 之前），添加 notFound 检查：

```swift
@ViewBuilder
private func partialResultView(_ partial: PartialWordResult) -> some View {
    if partial.notFound {
        notFoundView(partial)
    } else {
        // 原有的全部内容（从 partialCorrectionBanner 到末尾）
        partialCorrectionBanner(partial)
        // ... 其余不变
    }
}
```

需要将原有内容包裹在 else 分支中。

**Step 3: 在流式处理中 notFound 时跳过骨架屏**

在 `performTranslation` 的流式处理部分（约第 678 行），修改骨架屏隐藏条件：

```swift
if (partial.phonetic != nil || partial.notFound) && isLoading {
    isLoading = false
}
```

**Step 4: 流完成时 notFound 不转为正式 result**

在 `performTranslation` 中处理 `partial.isComplete` 的部分（约第 682-697 行），添加 notFound 检查：

```swift
if partial.isComplete {
    if partial.notFound {
        // notFound 保持在 partialWord 中显示空状态，不转为 result
        partialWord = partial
    } else {
        // 流式完成，转为正式 result
        result = TranslationResult(
            word: partial.word ?? "",
            phonetic: partial.phonetic ?? "",
            translation: partial.translation ?? "",
            examples: partial.examples,
            originalInput: partial.originalInput,
            etymology: partial.etymology,
            association: partial.association
        )
        partialWord = nil
        isSaved = WordBookManager.shared.isWordSaved(result!.word)
    }
} else {
    partialWord = partial
}
```

**Step 5: 构建验证**

Run: `xcodebuild -project SnapDict.xcodeproj -scheme SnapDict build 2>&1 | tail -3`
Expected: BUILD SUCCEEDED

**Step 6: Commit**

```bash
git add SnapDict/Views/TranslationContentView.swift
git commit -m "查词空状态：未找到的词显示建议按钮而非牵强翻译"
```
