# 错误拼写词"未找到"空状态设计

## 背景

用户输入拼写错误的词时，DeepSeek 自动纠正并显示纠错横幅。用户点击"仍查询 xxx"后，AI 被迫按原始输入翻译，但该词不存在时会硬编一个牵强的释义，体验不好。

## 目标

点击"仍查询"后，如果词确实不存在，显示清晰的空状态并提供纠正建议，而非展示牵强的翻译结果。

## 设计

### Prompt 变更

仅在 `forceNoAutoCorrect` 模式下，prompt 增加指令：

> 如果该词不是一个真实存在的英文单词，返回 `{"not_found": true, "suggestion": "你认为用户想查的正确单词"}`，不要硬编释义。如果是真实单词，按正常格式返回。

正常查询（有自动纠错）的 prompt 不变。

### 数据模型

`PartialWordResult` 新增：
- `notFound: Bool = false`
- `suggestion: String?`

### 流式解析

DeepSeekService 流式解析中检测 `not_found` 和 `suggestion` 字段，设置到 partial 并正常 yield。

### 界面

当 `notFound == true` 时，结果区域显示空状态：
- 居中警告图标 + "未找到该词"
- 如果 `suggestion` 非空，显示"您是否要查询 xxx？"按钮
- 点击建议按钮以正常模式（带自动纠错）查询该词
- 不显示发音、收藏、助记、例句等区域

### 触发范围

仅 `forceNoAutoCorrect = true` 时启用（即用户点击"仍查询"时），正常查询流程不受影响。

### 不缓存

`not_found` 的结果不缓存到 TranslationCache。
