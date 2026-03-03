import Foundation

enum Constants {
    enum API {
        static let deepSeekEndpoint = "https://api.deepseek.com/chat/completions"
        static let deepSeekModel = "deepseek-chat"

        static let dotBaseURL = "https://dot.mindreset.tech"
        static let dotDevicesPath = "/api/authV2/open/devices"
        static func dotTextPath(deviceId: String) -> String {
            "/api/authV2/open/device/\(deviceId)/text"
        }
        static func dotTaskListPath(deviceId: String, taskType: String = "loop") -> String {
            "/api/authV2/open/device/\(deviceId)/\(taskType)/list"
        }
        static func dotImagePath(deviceId: String) -> String {
            "/api/authV2/open/device/\(deviceId)/image"
        }

        static let byteDanceTTSEndpoint = "https://openspeech.bytedance.com/api/v3/tts/unidirectional"
        static let byteDanceTTSResourceId = "seed-tts-2.0"
        static let byteDanceTTSVoices: [(id: String, name: String)] = [
            ("en_female_stokie_uranus_bigtts", "Stokie(女)"),
            ("en_male_tim_uranus_bigtts", "Tim(男)"),
        ]
        static let byteDanceTTSDefaultVoice = "en_female_stokie_uranus_bigtts"
    }

    enum TTSEngine: String, CaseIterable {
        case system = "system"
        case byteDance = "byteDance"

        var displayName: String {
            switch self {
            case .system: return "系统发音"
            case .byteDance: return "豆包语音"
            }
        }
    }

    enum PushMode: String, CaseIterable {
        case text = "text"
        case image = "image"

        var displayName: String {
            switch self {
            case .text: return "文本"
            case .image: return "图片"
            }
        }
    }

    enum DitherType: String, CaseIterable {
        case none = "NONE"
        case diffusion = "DIFFUSION"
        case ordered = "ORDERED"

        var displayName: String {
            switch self {
            case .none: return "关闭抖动"
            case .diffusion: return "误差扩散"
            case .ordered: return "有序抖动"
            }
        }
    }

    enum DitherKernel: String, CaseIterable {
        case floydSteinberg = "FLOYD_STEINBERG"
        case jarvisJudiceNinke = "JARVIS_JUDICE_NINKE"
        case stucki = "STUCKI"
        case atkinson = "ATKINSON"
        case burkes = "BURKES"
        case sierra = "SIERRA"
        case twoRowSierra = "TWO_ROW_SIERRA"
        case sierraLite = "SIERRA_LITE"
        case simple2D = "SIMPLE_2D"
        case stevensonArce = "STEVENSON_ARCE"

        var displayName: String {
            switch self {
            case .floydSteinberg: return "Floyd-Steinberg"
            case .jarvisJudiceNinke: return "Jarvis-Judice-Ninke"
            case .stucki: return "Stucki"
            case .atkinson: return "Atkinson"
            case .burkes: return "Burkes"
            case .sierra: return "Sierra"
            case .twoRowSierra: return "Two-Row Sierra"
            case .sierraLite: return "Sierra Lite"
            case .simple2D: return "Simple 2D"
            case .stevensonArce: return "Stevenson-Arce"
            }
        }
    }

    enum UserDefaultsKey {
        static let deepSeekAPIKey = "deepSeekAPIKey"
        static let dotAPIKey = "dotAPIKey"
        static let pushInterval = "pushIntervalMinutes"
        static let pushOnlyLearning = "pushOnlyLearning"
        static let autoTranslate = "autoTranslateEnabled"
        static let pushEnabled = "pushEnabled"
        static let cachedDeviceId = "cachedDeviceId"
        static let cachedTaskKey = "cachedTaskKey"
        static let hotKeyKeyCode = "hotKeyKeyCode"
        static let hotKeyModifiers = "hotKeyModifiers"
        static let enableMnemonic = "enableMnemonic"
        static let showExamples = "showExamples"
        static let ttsEngine = "ttsEngine"
        static let byteDanceTTSAppId = "byteDanceTTSAppId"
        static let byteDanceTTSAPIKey = "byteDanceTTSAPIKey"
        static let ttsFallbackToSystem = "ttsFallbackToSystem"
        static let byteDanceTTSVoice = "byteDanceTTSVoice"
        static let hideOnFocusLost = "hideOnFocusLost"
        static let autoCorrect = "autoCorrect"
        static let autoFetchSelectedText = "autoFetchSelectedText"
        static let pushMode = "pushMode"
        static let ditherType = "ditherType"
        static let ditherKernel = "ditherKernel"
    }

    enum Defaults {
        static let pushIntervalMinutes = 30
        static let pushOnlyLearning = true
        static let autoTranslate = true
        static let enableMnemonic = true
        static let showExamples = true
        static let ttsFallbackToSystem = true
        static let hideOnFocusLost = true
        static let autoCorrect = false
        static let autoFetchSelectedText = false
        static let pushMode: PushMode = .text
        static let ditherType: DitherType = .none
        static let ditherKernel: DitherKernel = .floydSteinberg
    }

    enum Notification {
        static let openWordBook = Foundation.Notification.Name("SnapDict.openWordBook")
        static let openSettings = Foundation.Notification.Name("SnapDict.openSettings")
    }
}
