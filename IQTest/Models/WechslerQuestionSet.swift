import Foundation

/// 自编题组，尚未经过题组等值验证。
enum WechslerQuestionSet: String, Codable, CaseIterable, Identifiable {
    case a = "A", b = "B"
    var id: String { rawValue }
    var title: String { "题组 \(rawValue)" }
    var bankResource: String { self == .a ? "Wechsler" : "WechslerB" }
    var modelResource: String { self == .a ? "WechslerIQModel" : "WechslerIQModelB" }
}
