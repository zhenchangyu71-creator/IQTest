import Foundation

/// 年龄带仅用于基本信息展示，当前估算模型未作年龄校准。
enum AgeBand: String, CaseIterable, Identifiable {
    case child = "儿童"
    case teen = "青少年"
    case adult = "成人"
    case senior = "老年"

    var id: String { rawValue }

    init?(age: Int) {
        switch age {
        case 6...12: self = .child
        case 13...17: self = .teen
        case 18...59: self = .adult
        case 60...: self = .senior
        default: return nil
        }
    }

    /// 完整描述，如「成人（18–59 岁）」
    var title: String {
        switch self {
        case .child: return "儿童（6–12 岁）"
        case .teen: return "青少年（13–17 岁）"
        case .adult: return "成人（18–59 岁）"
        case .senior: return "老年（60 岁以上）"
        }
    }

    private static let storageKey = "testTakerAge"
    static let defaultAge = 25

    /// 当前被试年龄（首页输入，持久化保存）
    static var age: Int {
        get {
            UserDefaults.standard.object(forKey: storageKey) as? Int ?? defaultAge
        }
        set {
            UserDefaults.standard.set(newValue, forKey: storageKey)
        }
    }

    /// 当前被试的年龄带
    static var current: AgeBand {
        AgeBand(age: age) ?? .adult
    }
}
