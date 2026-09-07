import Foundation

/// In-app language override (Settings → Language), independent of the
/// system language — mirrors Android's LocaleManager. Native names are
/// always shown in their own script regardless of the current UI language,
/// same as Android's lang_en/lang_ml/... resources.
/// Order matches Android's language picker.
enum AppLanguage: String, CaseIterable, Identifiable {
    case en
    case hi
    case kn
    case ml
    case ta

    var id: String { rawValue }

    /// Native names come straight from Android's `lang_*` resources.
    var nativeName: String {
        switch self {
        case .en: return "English"
        case .hi: return "हिन्दी"
        case .kn: return "ಕನ್ನಡ"
        case .ml: return "മലയാളം"
        case .ta: return "தமிழ்"
        }
    }

    var locale: Locale { Locale(identifier: rawValue) }
}
