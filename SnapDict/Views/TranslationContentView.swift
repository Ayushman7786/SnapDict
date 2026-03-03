import SwiftUI
import SwiftData
import AVFoundation

struct TranslationContentView: View {
    /// 每次变化时重置所有状态（由 UnifiedPanelView 在 shouldReset 时更新）
    let resetID: UUID
    /// 当前 Tab 是否激活（控制输入框焦点）
    let isActive: Bool
    /// 外部传入的初始查询（选中文字），使用后自动清空
    @Binding var initialQuery: String?
    /// 内容区显示状态变化回调（供 UnifiedPanelView 控制面板高度）
    var onContentChange: ((Bool) -> Void)?
    /// 上报实际内容高度（供 PanelManager 自适应窗口高度）
    var onContentHeightChange: ((CGFloat) -> Void)?

    @State private var query = ""
    @State private var result: TranslationResult?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isSaved = false
    @State private var debounceTask: Task<Void, Never>?
    @State private var translationTask: Task<Void, Never>?
    @State private var isSpeaking = false
    @State private var isMnemonicLoading = false
    @State private var isExamplesLoading = false
    @State private var mnemonicError: String?
    @State private var examplesError: String?
    @State private var mnemonicTask: Task<Void, Never>?
    @State private var examplesTask: Task<Void, Never>?
    @State private var correctionDismissed = false
    @State private var shimmerPhase: CGFloat = -200

    private let synthesizer = AVSpeechSynthesizer()

    @State private var contentHeight: CGFloat = 0

    @FocusState private var isInputFocused: Bool

    // 判断是否有内容显示（需要展开窗口）
    private var hasContent: Bool {
        isLoading || errorMessage != nil || result != nil
    }

    /// 是否有任何骨架屏可见（主骨架屏或助记/例句骨架屏），用于控制闪烁动画
    private var isAnySkeletonVisible: Bool {
        if isLoading { return true }
        guard result != nil else { return false }
        let hasMnemonicData = result?.etymology != nil || result?.association != nil
        let hasExamples = !(result?.examples.isEmpty ?? true)
        return (isMnemonicLoading && !hasMnemonicData) || (isExamplesLoading && !hasExamples)
    }

    /// 骨架屏预估内容高度，用于在 onGeometryChange 触发前立即展开面板
    private var estimatedSkeletonContentHeight: CGFloat {
        // 基础：单词行 + 2 行翻译 + 间距 + padding
        var h: CGFloat = 106
        if UserDefaults.standard.object(forKey: Constants.UserDefaultsKey.enableMnemonic) as? Bool
            ?? Constants.Defaults.enableMnemonic { h += 99 }
        if UserDefaults.standard.object(forKey: Constants.UserDefaultsKey.showExamples) as? Bool
            ?? Constants.Defaults.showExamples { h += 98 }
        return h
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar - Spotlight style
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 22, weight: .light))

                TextField("输入单词或短语...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 22, weight: .light))
                    .focused($isInputFocused)
                    .onSubmit {
                        debounceTask?.cancel()
                        performTranslation()
                    }
                    .onChange(of: query) { _, newValue in
                        if newValue.isEmpty {
                            resetState()
                        } else {
                            debounceAutoTranslate(newValue)
                        }
                    }

                if !query.isEmpty {
                    Button {
                        resetState()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                            .font(.system(size: 16))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            if hasContent {
                Divider()
                    .padding(.horizontal, 8)

                // Content area
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if isLoading {
                            skeletonView()
                        } else if let error = errorMessage {
                            HStack {
                                Spacer()
                                VStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle")
                                        .font(.title2)
                                        .foregroundStyle(.orange)
                                    Text(error)
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                                Spacer()
                            }
                            .padding(.top, 40)
                        } else if let result {
                            resultView(result)
                        }
                    }
                    .padding(16)
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { newHeight in
                        contentHeight = newHeight
                    }
                }
            }
        }
        .frame(width: 420)
        .background(.clear)
        .onChange(of: contentHeight) { _, newHeight in
            if hasContent {
                onContentHeightChange?(newHeight)
            }
        }
        .onChange(of: hasContent) { _, newValue in
            if newValue {
                // 立即上报预估内容高度，触发面板展开，
                // 不等待 onGeometryChange 异步布局回调。
                // 防止快速 API 响应在布局完成前到达导致面板不展开。
                if contentHeight <= 0 {
                    onContentHeightChange?(estimatedSkeletonContentHeight)
                }
            } else {
                // 重置，确保下次内容出现时 onChange(of: contentHeight) 可靠触发
                contentHeight = 0
            }
            DispatchQueue.main.async {
                self.onContentChange?(newValue)
            }
        }
        .onChange(of: resetID) { _, _ in
            resetState()
            if isActive { isInputFocused = true }
            // reset 后检查是否有待填入的选中文字
            if let text = initialQuery, !text.isEmpty {
                query = text
                initialQuery = nil
                performTranslation()
            }
        }
        .onChange(of: initialQuery) { _, newValue in
            // 非 reset 场景下的选中文字填入（面板未重置时）
            if let text = newValue, !text.isEmpty {
                query = text
                initialQuery = nil
                performTranslation()
            }
        }
        .onChange(of: isActive) { _, newValue in
            if newValue {
                isInputFocused = true
                DispatchQueue.main.async {
                    self.onContentChange?(self.hasContent)
                }
            }
        }
        .onKeyPress(.escape) {
            if query.isEmpty {
                return .ignored
            }
            resetState()
            return .handled
        }
        .onChange(of: isAnySkeletonVisible) { _, visible in
            if visible {
                shimmerPhase = -200
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    shimmerPhase = 400
                }
            } else {
                shimmerPhase = -200
            }
        }
        .onAppear {
            if isActive {
                isInputFocused = true
            }
        }
    }

    // MARK: - Skeleton

    private func skeletonLine(width: CGFloat, height: CGFloat = 14) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(.quaternary)
            .frame(width: width, height: height)
    }

    /// 为骨架内容添加从左到右扫过的光波闪烁效果
    private func withShimmer<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        content()
            .overlay(
                LinearGradient(
                    gradient: Gradient(colors: [.clear, .white.opacity(0.4), .clear]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 120)
                .offset(x: shimmerPhase)
                .mask { content() }
            )
    }

    @ViewBuilder
    private func skeletonView() -> some View {
        let enableMnemonic = UserDefaults.standard.object(forKey: Constants.UserDefaultsKey.enableMnemonic) as? Bool
            ?? Constants.Defaults.enableMnemonic
        let showExamples = UserDefaults.standard.object(forKey: Constants.UserDefaultsKey.showExamples) as? Bool
            ?? Constants.Defaults.showExamples

        withShimmer {
            VStack(alignment: .leading, spacing: 12) {
                // 单词行：word + phonetic + bookmark
                HStack {
                    skeletonLine(width: 120, height: 22)
                    skeletonLine(width: 60, height: 15)
                    Spacer()
                    skeletonLine(width: 20, height: 20)
                }

                // 翻译
                skeletonLine(width: 280)
                skeletonLine(width: 180)

                // 助记
                if enableMnemonic {
                    Divider()
                        .padding(.vertical, 4)

                    HStack(spacing: 4) {
                        skeletonLine(width: 14, height: 14)
                        skeletonLine(width: 30, height: 13)
                    }
                    skeletonLine(width: 240)
                    skeletonLine(width: 300)
                }

                // 例句
                if showExamples {
                    Divider()
                        .padding(.vertical, 4)

                    skeletonLine(width: 30, height: 13)
                    skeletonLine(width: 340)
                    skeletonLine(width: 260)
                }
            }
        }
    }

    /// 助记区域骨架屏（词根 + 联想占位）
    @ViewBuilder
    private func mnemonicSkeletonContent() -> some View {
        withShimmer {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    skeletonLine(width: 28, height: 12)
                    skeletonLine(width: 240)
                }
                VStack(alignment: .leading, spacing: 4) {
                    skeletonLine(width: 28, height: 12)
                    skeletonLine(width: 300)
                }
            }
        }
    }

    /// 例句区域骨架屏
    @ViewBuilder
    private func examplesSkeletonContent() -> some View {
        withShimmer {
            VStack(alignment: .leading, spacing: 8) {
                skeletonLine(width: 340)
                skeletonLine(width: 260)
            }
        }
    }

    // MARK: - Result

    @ViewBuilder
    private func resultView(_ result: TranslationResult) -> some View {
        // 拼写纠正提示
        correctionBanner(result)

        // Word + phonetic + save button
        HStack(alignment: .center) {
            Text(result.word)
                .font(.system(size: 22, weight: .semibold))

            if !result.phonetic.isEmpty {
                Text(result.phonetic)
                    .font(.system(size: 15, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Button {
                speakWord(result.word)
            } label: {
                Image(systemName: isSpeaking ? "waveform" : "speaker.wave.2")
                    .font(.system(size: 16))
                    .foregroundStyle(isSpeaking ? Color.accentColor : .secondary)
                    .symbolEffect(.variableColor, isActive: isSpeaking)
            }
            .buttonStyle(.plain)
            .help("朗读 (⌘S)")
            .keyboardShortcut("s", modifiers: .command)

            Spacer()

            Button {
                toggleSaveWord(result)
            } label: {
                Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 18))
                    .foregroundStyle(isSaved ? .orange : .secondary)
            }
            .buttonStyle(.plain)
            .help(isSaved ? "取消收藏 (⌘D)" : "保存到生词本 (⌘D)")
            .keyboardShortcut("d", modifiers: .command)
        }

        // Translation
        Text(result.translation)
            .font(.system(size: 16))
            .foregroundStyle(.primary)
            .textSelection(.enabled)

        // Mnemonic (助记：词根 + 联想)
        mnemonicSection(result)

        // Examples (例句)
        examplesSection(result)
    }

    @ViewBuilder
    private func correctionBanner(_ result: TranslationResult) -> some View {
        if let originalInput = result.originalInput {
            // 自动纠正已执行：显示纠正信息 + 回退按钮
            HStack(spacing: 6) {
                Image(systemName: "character.cursor.ibeam")
                    .font(.system(size: 12))
                Text("已自动纠正: \"\(originalInput)\" → \"\(result.word)\"")
                    .font(.system(size: 13))
                Spacer()
                Button {
                    queryWithOriginalInput(originalInput)
                } label: {
                    Text("仍查询 \(originalInput)")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
            .foregroundStyle(.secondary)
        } else if let suggestion = result.suggestedCorrection, !correctionDismissed {
            // 未自动纠正但检测到可能拼写错误：提示用户
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                Text("可能拼写有误，你要找的是 \"\(suggestion)\" 吗？")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    queryWithSuggestion(suggestion)
                } label: {
                    Text("查询 \(suggestion)")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                Button {
                    correctionDismissed = true
                } label: {
                    Text("忽略")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func performTranslation(forceNoAutoCorrect: Bool = false) {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        correctionDismissed = false
        isLoading = true
        errorMessage = nil
        result = nil
        isSaved = false
        isMnemonicLoading = false
        isExamplesLoading = false
        mnemonicError = nil
        examplesError = nil
        mnemonicTask?.cancel()
        examplesTask?.cancel()

        translationTask = Task {
            // 阶段 1：查词
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
        }
    }

    private func debounceAutoTranslate(_ text: String) {
        // 取消防抖任务
        debounceTask?.cancel()
        // 若有正在进行的查询，立即中断并清除结果，等待用户输入完成后重新查询
        // 保持 isLoading = true 让骨架屏持续显示，避免面板塌缩闪烁
        if isLoading || isMnemonicLoading || isExamplesLoading {
            translationTask?.cancel()
            mnemonicTask?.cancel()
            examplesTask?.cancel()
            isLoading = true
            isMnemonicLoading = false
            isExamplesLoading = false
            result = nil
            errorMessage = nil
            mnemonicError = nil
            examplesError = nil
        }
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            performTranslation()
        }
    }

    private func resetState() {
        debounceTask?.cancel()
        translationTask?.cancel()
        mnemonicTask?.cancel()
        examplesTask?.cancel()
        isLoading = false
        isMnemonicLoading = false
        isExamplesLoading = false
        query = ""
        result = nil
        errorMessage = nil
        mnemonicError = nil
        examplesError = nil
        isSaved = false
        correctionDismissed = false
    }

    private func speakWord(_ word: String) {
        // 若正在播放则停止
        if isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
            Task { await ByteDanceTTSService.shared.stop() }
            isSpeaking = false
            return
        }

        let engineRaw = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.ttsEngine) ?? ""
        let engine = Constants.TTSEngine(rawValue: engineRaw) ?? .system

        isSpeaking = true
        Task {
            defer { isSpeaking = false }
            switch engine {
            case .system:
                let utterance = AVSpeechUtterance(string: word)
                utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
                utterance.rate = 0.45
                synthesizer.speak(utterance)
                while synthesizer.isSpeaking {
                    try? await Task.sleep(for: .milliseconds(100))
                }
            case .byteDance:
                do {
                    try await ByteDanceTTSService.shared.speak(word)
                } catch {
                    let fallback = UserDefaults.standard.object(forKey: Constants.UserDefaultsKey.ttsFallbackToSystem) as? Bool
                        ?? Constants.Defaults.ttsFallbackToSystem
                    if fallback {
                        let utterance = AVSpeechUtterance(string: word)
                        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
                        utterance.rate = 0.45
                        synthesizer.speak(utterance)
                        while synthesizer.isSpeaking {
                            try? await Task.sleep(for: .milliseconds(100))
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func mnemonicSection(_ result: TranslationResult) -> some View {
        let enableMnemonic = UserDefaults.standard.object(forKey: Constants.UserDefaultsKey.enableMnemonic) as? Bool
            ?? Constants.Defaults.enableMnemonic
        let hasMnemonicData = result.etymology != nil || result.association != nil

        if enableMnemonic {
            Divider()
                .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "lightbulb")
                        .font(.system(size: 12))
                    Text("助记")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)

                    if isMnemonicLoading {
                        ProgressView()
                            .controlSize(.mini)
                    } else if hasMnemonicData {
                        Button { refreshMnemonic() } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    } else if mnemonicError != nil {
                        Button { refreshMnemonic() } label: {
                            Text("重试")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button { refreshMnemonic() } label: {
                            Text("生成")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let error = mnemonicError, !hasMnemonicData {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                }

                if isMnemonicLoading && !hasMnemonicData {
                    mnemonicSkeletonContent()
                }

                Group {
                    if let etymology = result.etymology {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("词根")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                            Text(etymology)
                                .font(.system(size: 14))
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                        }
                    }

                    if let association = result.association {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("联想")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                            Text(association)
                                .font(.system(size: 14))
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: hasMnemonicData)
            }
        }
    }

    @ViewBuilder
    private func examplesSection(_ result: TranslationResult) -> some View {
        let showExamples = UserDefaults.standard.object(forKey: Constants.UserDefaultsKey.showExamples) as? Bool
            ?? Constants.Defaults.showExamples
        let hasExamples = !result.examples.isEmpty

        if showExamples {
            Divider()
                .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "text.quote")
                        .font(.system(size: 12))
                    Text("例句")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)

                    if isExamplesLoading {
                        ProgressView()
                            .controlSize(.mini)
                    } else if hasExamples {
                        Button { refreshExamples() } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    } else if examplesError != nil {
                        Button { refreshExamples() } label: {
                            Text("重试")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button { refreshExamples() } label: {
                            Text("生成")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let error = examplesError, !hasExamples {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                }

                if isExamplesLoading && !hasExamples {
                    examplesSkeletonContent()
                }

                Group {
                    ForEach(result.examples, id: \.self) { example in
                        Text(example)
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: hasExamples)
            }
        }
    }

    private func refreshMnemonic() {
        guard let result = result, !isMnemonicLoading else { return }

        mnemonicTask?.cancel()
        mnemonicTask = Task {
            isMnemonicLoading = true
            mnemonicError = nil
            do {
                let mnemonic = try await DeepSeekService.shared.fetchMnemonic(result.word, skipCache: true)
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

    private func refreshExamples() {
        guard let result = result, !isExamplesLoading else { return }

        examplesTask?.cancel()
        examplesTask = Task {
            isExamplesLoading = true
            examplesError = nil
            do {
                let examples = try await DeepSeekService.shared.fetchExamples(result.word, translation: result.translation, skipCache: true)
                guard !Task.isCancelled else { return }
                self.result?.examples = examples
            } catch {
                guard !Task.isCancelled else { return }
                self.examplesError = error.localizedDescription
            }
            self.isExamplesLoading = false
        }
    }

    /// 用户选择使用原始输入重新查询（强制不纠正）
    private func queryWithOriginalInput(_ text: String) {
        query = text
        debounceTask?.cancel()
        performTranslation(forceNoAutoCorrect: true)
    }

    /// 用户选择使用建议的纠正词查询
    private func queryWithSuggestion(_ text: String) {
        query = text
        debounceTask?.cancel()
        performTranslation()
    }

    private func toggleSaveWord(_ result: TranslationResult) {
        do {
            if isSaved {
                try WordBookManager.shared.deleteWord(byName: result.word)
                isSaved = false
            } else {
                try WordBookManager.shared.saveWord(from: result)
                isSaved = true
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
