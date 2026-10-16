import Foundation

/// 年龄带：用于按年龄校准常模换算（简化模型）
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

    /// 瑞文换算：对该难度期望得分率的修正。
    /// 题目按成人设计，儿童/青少年达到同分时应换算出更高的 IQ，故降低期望得分率
    var ravenMeanOffset: Double {
        switch self {
        case .child: return -0.10
        case .teen: return -0.05
        case .adult: return 0
        case .senior: return -0.025
        }
    }

    /// 韦氏换算：对量表分的修正（年龄常模：同表现下低龄被试得到更高的年龄校准量表分）
    var wechslerScaledOffset: Int {
        switch self {
        case .child: return 2
        case .teen: return 1
        case .adult: return 0
        case .senior: return 1
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
