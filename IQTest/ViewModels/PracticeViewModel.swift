import Foundation

/// 与旧版量表分分开存储，避免将旧 1–19 分误读为得分率。
enum PracticeStore {
    private static let key = "wechslerPracticePercentagesV2"
    private static var stats: [String: [String: Int]] {
        get { UserDefaults.standard.object(forKey: key) as? [String: [String: Int]] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static func recordAttempt(subtest: WechslerSubtest, percentage: Int) {
        var all = stats
        var entry = all[subtest.rawValue] ?? [:]
        entry["count"] = (entry["count"] ?? 0) + 1
        entry["best"] = max(entry["best"] ?? 0, min(100, max(0, percentage)))
        all[subtest.rawValue] = entry
        stats = all
    }

    static func best(subtest: WechslerSubtest) -> Int? { stats[subtest.rawValue]?["best"] }
    static func count(subtest: WechslerSubtest) -> Int { stats[subtest.rawValue]?["count"] ?? 0 }
}

@MainActor
final class PracticeViewModel: WechslerViewModel {
    var subtest: WechslerSubtest { currentSubtest }
    var progress: Double { totalProgress }
    var performanceComment: String {
        interruptedCount > 0 ? "中断题未计分，本次不更新练习次数和最佳成绩。"
            : "本组得分率仅描述这三题的表现，不与同龄人比较。"
    }
    func start(_ subtest: WechslerSubtest) { start(practice: subtest) }
    func backToPicker() { reset() }
}
