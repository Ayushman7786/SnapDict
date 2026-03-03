# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Development

```bash
# 生成 Xcode 工程（新增/删除文件后必须执行）
xcodegen generate

# 命令行构建
xcodebuild -project SnapDict.xcodeproj -scheme SnapDict build

# 打开 Xcode
open SnapDict.xcodeproj
```

- 使用 XcodeGen 管理工程文件，`sources: [SnapDict]` 自动包含目录下所有 Swift 文件
- 新增或删除 .swift 文件后需重新运行 `xcodegen generate`
- 无测试套件

## Architecture

macOS 菜单栏翻译词典应用（LSUIElement），Swift 6.0 + SwiftUI + SwiftData。

**分层结构：**

- **Models/** — SwiftData `@Model` 类（WordEntry, TranslationCache, TTSCache）和 Codable 数据结构（TranslationResult）
- **Services/** — 外部 API 调用和业务逻辑（DeepSeekService, DotScreenService, ByteDanceTTSService, CacheService, WordCardRenderer）
- **Managers/** — 应用状态管理（PanelManager 管理浮动窗口, WordBookManager 管理 SwiftData CRUD, WordPushScheduler 定时推送）
- **Views/** — SwiftUI 界面，UnifiedPanelView 包含 3 个 Tab（查词、单词本、设置）
- **Utilities/Constants.swift** — 所有 API 端点、UserDefaults key、默认值集中定义

**核心数据流：**
HotKeyManager → PanelManager.showPanel() → TranslationContentView → DeepSeekService（翻译/助记/例句）→ CacheService → WordBookManager → WordPushScheduler → DotScreenService

## Concurrency Model

项目启用 `SWIFT_STRICT_CONCURRENCY: complete`，编译时严格检查并发安全：

- `@MainActor @Observable`: PanelManager, WordBookManager, WordPushScheduler, HotKeyManager — 所有 UI 和 SwiftData 操作
- `@Observable final class: Sendable`: DeepSeekService, DotScreenService — API 服务
- `actor`: ByteDanceTTSService — 音频处理
- `@unchecked Sendable`: CacheService — 内部使用 DispatchQueue

跨线程调用用 `Task { @MainActor in ... }` 或 `await`。

## Conventions

- Git commit message 使用中文编写
- 所有配置项通过 `Constants.UserDefaultsKey` 和 `Constants.Defaults` 集中管理
- API 请求统一模式：URLRequest → URLSession.shared.data() → 状态码检查 → JSON 解码
- 面板动画使用 CASpringAnimation（PanelManager）
- SwiftData 查询用 FetchDescriptor + #Predicate（Manager 中）或 @Query（View 中）

# currentDate
Today's date is 2026-03-02.
