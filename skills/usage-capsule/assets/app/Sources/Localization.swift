import Foundation

enum CapsuleLanguage:String, CaseIterable {
    case system, chinese="zh-Hans", english="en", japanese="ja", korean="ko"
    var title:String {
        switch self {
        case .system: return L10n.text("跟随系统")
        case .chinese: return "简体中文"
        case .english: return "English"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        }
    }
    static func resolve(selection:String,preferred:[String]) -> String {
        if let selected=Self(rawValue:selection), selected != .system { return selected.rawValue }
        for code in preferred {
            let base=code.lowercased().replacingOccurrences(of:"_",with:"-")
            if base == "zh" || base.hasPrefix("zh-") { return "zh-Hans" }
            if base == "en" || base.hasPrefix("en-") { return "en" }
            if base == "ja" || base.hasPrefix("ja-") { return "ja" }
            if base == "ko" || base.hasPrefix("ko-") { return "ko" }
        }
        return "en"
    }
}

enum L10n {
    static var languageCode:String {
        let selection=ProcessInfo.processInfo.environment["USAGE_CAPSULE_LANGUAGE"] ?? UserDefaults.standard.string(forKey:"interfaceLanguage") ?? "system"
        return CapsuleLanguage.resolve(selection:selection,preferred:Locale.preferredLanguages)
    }
    static func text(_ key:String) -> String {
        let path=Bundle.main.path(forResource:languageCode,ofType:"lproj") ?? Bundle.main.path(forResource:"en",ofType:"lproj")
        let bundle=path.flatMap(Bundle.init(path:)) ?? Bundle.main
        return bundle.localizedString(forKey:key,value:key,table:"Localizable")
    }
    static func format(_ key:String,_ arguments:CVarArg...) -> String {
        String(format:text(key),locale:Locale(identifier:languageCode),arguments:arguments)
    }
}
