# 短句和片段翻译支持设计

## 背景

SnapDict 当前围绕单词设计，翻译 Prompt、数据模型、UI 展示都偏向单词场景。用户需要在阅读划词、代码注释、短句学习、中译英等场景中翻译短句和片段，但现有体验存在两个主要痛点：

1. 翻译结果格式（word + phonetic + translation）不适合短句
2. 弹窗宽度不够展示长文本

## 方案选择

**方案 A：统一入口，智能分流**（已确认）

保持单一搜索框，自动判断输入类型（英文单词 / 英文短句 / 中文），走不同的处理流水线。不增加模式切换按钮，保持 SnapDict "快捷键即出结果"的核心体验。

## 详细设计

### 1. 输入类型检测

新建 `InputClassifier` 工具类，使用固定规则判断输入类型：

- **chinese**：包含中文字符（Unicode CJK 范围）→ 中译英
- **word**：纯英文，不含空格或仅含 1 个空格且总长度 ≤ 20 → 走现有词典流水线
- **sentence**：纯英文，含空格且超过 word 阈值 → 英文短句翻译

检测在本地完成（<1ms），不依赖 API。

### 2. 翻译 Prompt

#### 英文短句（sentence）

```
你是一个专业的英语翻译助手。请翻译以下英文短句/段落，只返回 JSON 格式：
{"translation": "中文翻译（自然流畅）", "analysis": "简要语法/用法解析（2-3句话，点出关键语法点或地道用法）"}
```

#### 中译英（chinese）

```
你是一个专业的英语翻译助手。请将以下中文翻译为英文，只返回 JSON 格式：
{"translation": "英文翻译（自然地道）", "analysis": "简要用法说明（解释翻译选择或提供替代表达）"}
```

关键参数：
- 温度 0.1（保持输出稳定）
- 不返回原文（用户输入即原文，省 token 提升速度）
- 不需要拼写纠正逻辑
- analysis 控制在 2-3 句话

#### 单词（word）

保持现有 Prompt 不变。

### 3. 数据模型

#### SentenceTranslationResult（新增）

```swift
struct SentenceTranslationResult: Codable, Sendable {
    let translation: String   // 译文
    let analysis: String?     // 语法/用法解析
}
```

#### SentenceEntry（新增 SwiftData 模型）

```swift
@Model final class SentenceEntry {
    @Attribute(.unique) var original: String   // 原文（唯一键）
    var translation: String                     // 译文
    var analysis: String?                       // 语法/用法解析
    var sourceLanguage: String                  // "en" 或 "zh"
    var createdAt: Date                         // 收藏时间
}
```

与 WordEntry 分开管理，独立的句子本。

### 4. 缓存策略

复用现有 `TranslationCache` 模型：
- key 归一化：`.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)`
- 中文输入也缓存（key 为中文原文）
- 短句缓存命中率预期低于单词，可接受

### 5. UI 自适应

#### 弹窗宽度

- word 类型：保持现有宽度（约 360pt）
- sentence / chinese 类型：加宽到约 480pt
- 宽度变化通过 `CASpringAnimation` 平滑过渡

触发时机：类型检测完成后立刻调整（防抖 300ms 后）。

#### 短句翻译结果布局

```
┌──────────────────────────┐
│ 🔍 [搜索框]              │
├──────────────────────────┤
│ 原文（灰色小字，取自输入）│
│ 译文（主文字，可选中复制） │
├──────────────────────────┤
│ 📝 语法/用法解析          │
│ 解析内容（次要文字）      │
├──────────────────────────┤
│ [收藏] [复制译文]         │
└──────────────────────────┘
```

#### 单词本 Tab

在现有单词本 Tab 中增加分段切换：「单词」/「句子」。

### 6. 文件变更清单

#### 新增

| 文件 | 说明 |
|------|------|
| `Utilities/InputClassifier.swift` | 输入类型检测 |
| `Models/SentenceTranslationResult.swift` | 短句翻译结果模型 |
| `Models/SentenceEntry.swift` | 句子本 SwiftData 模型 |
| `Views/SentenceTranslationView.swift` | 短句翻译结果视图 |
| `Views/PanelSentenceBookView.swift` | 句子本列表视图 |

#### 修改

| 文件 | 变更 |
|------|------|
| `Services/DeepSeekService.swift` | 新增 `translateSentence()` 方法 |
| `Services/CacheService.swift` | 支持短句缓存读写 |
| `Managers/PanelManager.swift` | 弹窗宽度自适应 |
| `Views/TranslationContentView.swift` | 根据类型切换单词/短句视图 |
| `Views/PanelWordBookView.swift` | 增加单词/句子分段切换 |

#### 不改动

- 现有单词翻译全流程
- TTS 朗读、墨水屏推送（暂不涉及短句）
- 设置页（短句功能默认开启）

## 不包含在此版本

- 句子本推送到墨水屏
- 短句 TTS 朗读
- 句子本导出功能
