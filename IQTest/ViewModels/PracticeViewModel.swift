import Foundation

/// 分测验练习成绩（按分测验持久化）
enum PracticeStore {
    private static let key = "wechslerPracticeStats"

    private static var stats: [String: [String: Int]] {
        get { UserDefaults.standard.object(forKey: key) as? [String: [String: Int]] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static func recordAttempt(subtest: WechslerSubtest, scaled: Int) {
        var all = stats
        var entry = all[subtest.rawValue] ?? [:]
        entry["count"] = (entry["count"] ?? 0) + 1
        entry["best"] = max(entry["best"] ?? 0, scaled)
        all[subtest.rawValue] = entry
        stats = all
    }

    static func best(subtest: WechslerSubtest) -> Int {
        stats[subtest.rawValue]?["best"] ?? 0
    }

    static func count(subtest: WechslerSubtest) -> Int {
        stats[subtest.rawValue]?["count"] ?? 0
    }
}

/// 分测验练习模式：
/// 任选 1 个韦氏分测验，分层抽取 3 题（低/中/高段各 1 题）单独训练；
/// 结束后给出估计量表分并记录该分测验的历史最佳。
@MainActor
final class PracticeViewModel: ObservableObject {
    enum Phase: Equatable {
        case picker
        case stimulus   // 数字广度：呈现数字阶段
        case question
        case done
    }

    @Published private(set) var phase: Phase = .picker
    @Published private(set) var subtest: WechslerSubtest = .block
    @Published private(set) var itemNumber = 0       // 第几题（1 起）
    @Published private(set) var stimulusRemaining = 0
    @Published private(set) var timeRemaining = 0
    @Published private(set) var presentedOptions: [Option] = []
    @Published private(set) var rawScore = 0
    @Published private(set) var maxRaw = 0

    struct Option: Identifiable {
        let id = UUID()
        let text: String
        let score: Int
    }

    private var items: [WechslerItem] = []

    var currentItem: WechslerItem? {
        items[safe: itemNumber - 1]
    }

    var itemCount: Int { items.count }

    var progress: Double {
        guard !items.isEmpty else { return 0 }
        return Double(itemNumber - 1) / Double(items.count)
    }

    /// 估计量表分：按本组 3 题的满分归一，再加年龄常模校准
    var estimatedScaled: Int {
        let base = WechslerScoring.scaled(raw: rawScore, maxRaw: maxRaw)
        return min(19, max(1, base + AgeBand.current.wechslerScaledOffset))
    }

    var scaledComment: String {
        switch estimatedScaled {
        case 16...: return "表现出色，接近该分测验上限！"
        case 13...: return "表现良好，高于平均水平。"
        case 10...: return "处于平均水平，继续巩固。"
        case 7...:  return "略低于平均，建议多练同类型题目。"
        default:    return "该分测验是短板，建议重点训练。"
        }
    }

    // MARK: - 流程控制

    /// 分层抽样：题库低/中/高段各取 1 题，兼顾难度覆盖
    func start(_ subtest: WechslerSubtest) {
        let pool = Dictionary(grouping: WechslerLoader.load(), by: { $0.subtest })[subtest] ?? []
        guard !pool.isEmpty else { return }
        let lows = Array(pool.prefix(4))
        let mids = Array(pool.dropFirst(4).prefix(4))
        let highs = Array(pool.dropFirst(8))
        var picked: [WechslerItem] = []
        if let item = lows.randomElement() { picked.append(item) }
        if let item = mids.randomElement() { picked.append(item) }
        if let item = highs.randomElement() { picked.append(item) }
        guard picked.count == 3 else { return }

        self.subtest = subtest
        items = picked
        maxRaw = picked.count * subtest.maxPointsPerItem
        rawScore = 0
        itemNumber = 1
        presentCurrentItem()
    }

    func backToPicker() {
        phase = .picker
    }

    func tick() {
        switch phase {
        case .stimulus:
            stimulusRemaining -= 1
            if stimulusRemaining <= 0 {
                timeRemaining = subtest.timeLimit
                phase = .question
            }
        case .question:
            timeRemaining -= 1
            if timeRemaining <= 0 {
                record(0) // 超时视为未通过
            }
        default:
            break
        }
    }

    func record(_ score: Int) {
        guard phase == .question, let item = currentItem else { return }
        phase = .picker // 防止重复提交
        rawScore += score
        if itemNumber >= items.count {
            PracticeStore.recordAttempt(subtest: subtest, scaled: estimatedScaled)
            phase = .done
        } else {
            itemNumber += 1
            presentCurrentItem()
        }
    }

    // MARK: - 私有

    private func presentCurrentItem() {
        guard let item = currentItem else { phase = .done; return }
        presentedOptions = zip(item.options, item.optionScores)
            .map { Option(text: $0.0, score: $0.1) }
            .shuffled()
        if item.presentation == "digits" {
            stimulusRemaining = item.displaySeconds ?? 4
            phase = .stimulus
        } else {
            timeRemaining = item.subtest.timeLimit
            phase = .question
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
