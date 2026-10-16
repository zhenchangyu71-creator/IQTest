import Foundation

/// 韦氏标准施测流程：
/// 10 个分测验按 WAIS 顺序施测；分测验内按难度递进；
/// 同一分测验连续 3 次得 0 分提前进入下一分测验（停测规则）。
@MainActor
final class WechslerViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case stimulus   // 数字广度：呈现数字阶段
        case question
        case finished
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var currentSubtest: WechslerSubtest = .block
    @Published private(set) var itemNumber = 0       // 分测验内第几题（1 起）
    @Published private(set) var itemsInSubtest = 0
    @Published private(set) var stimulusRemaining = 0
    @Published private(set) var timeRemaining = 0
    /// 当前题目的乱序选项（含得分）
    @Published private(set) var presentedOptions: [Option] = []

    struct Option: Identifiable {
        let id = UUID()
        let text: String
        let score: Int
    }

    // MARK: - 结果

    private(set) var results: [WechslerScoring.SubtestResult] = []
    private(set) var indexScores: [(domain: WechslerDomain, score: Int)] = []
    private(set) var fsiq = 0
    private(set) var percentileValue = 0

    // MARK: - 内部状态

    private var pool: [WechslerSubtest: [WechslerItem]] = [:]
    private var raw: [WechslerSubtest: Int] = [:]
    private var consecutiveFails = 0
    private var administeredItems = 0
    private var fullScoreItems = 0

    var currentItem: WechslerItem? {
        pool[currentSubtest]?[safe: itemNumber - 1]
    }

    var totalProgress: Double {
        let total = pool.values.reduce(0) { $0 + $1.count }
        guard total > 0 else { return 0 }
        let doneBeforeSubtest = WechslerSubtest.allCases
            .prefix(while: { $0 != currentSubtest })
            .reduce(0) { $0 + (pool[$1]?.count ?? 0) }
        return Double(doneBeforeSubtest + itemNumber - 1) / Double(total)
    }

    // MARK: - 流程控制

    func start() {
        let items = WechslerLoader.load()
        guard !items.isEmpty else { return }
        pool = Dictionary(grouping: items, by: { $0.subtest })
        raw = Dictionary(uniqueKeysWithValues: WechslerSubtest.allCases.map { ($0, 0) })
        results = []
        indexScores = []
        fsiq = 0
        percentileValue = 0
        consecutiveFails = 0
        administeredItems = 0
        fullScoreItems = 0
        currentSubtest = WechslerSubtest.allCases[0]
        itemNumber = 1
        itemsInSubtest = pool[currentSubtest]?.count ?? 0
        presentCurrentItem()
    }

    func reset() {
        phase = .idle
    }

    func tick() {
        switch phase {
        case .stimulus:
            stimulusRemaining -= 1
            if stimulusRemaining <= 0 {
                timeRemaining = currentSubtest.timeLimit
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
        phase = .idle // 防止重复提交
        raw[item.subtest, default: 0] += score
        administeredItems += 1
        if score == item.subtest.maxPointsPerItem { fullScoreItems += 1 }
        consecutiveFails = score == 0 ? consecutiveFails + 1 : 0

        if consecutiveFails >= 3 || itemNumber >= itemsInSubtest {
            advanceSubtest()
        } else {
            itemNumber += 1
            presentCurrentItem()
        }
    }

    // MARK: - 私有

    private func presentCurrentItem() {
        guard let item = currentItem else { advanceSubtest(); return }
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

    private func advanceSubtest() {
        guard let index = WechslerSubtest.allCases.firstIndex(of: currentSubtest),
              index + 1 < WechslerSubtest.allCases.count else {
            finish()
            return
        }
        currentSubtest = WechslerSubtest.allCases[index + 1]
        itemNumber = 1
        itemsInSubtest = pool[currentSubtest]?.count ?? 0
        consecutiveFails = 0
        if itemsInSubtest == 0 {
            advanceSubtest()
        } else {
            presentCurrentItem()
        }
    }

    private func finish() {
        phase = .finished
        let scaledOffset = AgeBand.current.wechslerScaledOffset
        results = WechslerSubtest.allCases.map { subtest in
            let maxRaw = (pool[subtest]?.count ?? 1) * subtest.maxPointsPerItem
            let r = raw[subtest] ?? 0
            let base = WechslerScoring.scaled(raw: r, maxRaw: maxRaw)
            // 年龄常模：同表现下低龄被试得到更高的年龄校准量表分
            let scaled = min(19, max(1, base + scaledOffset))
            return WechslerScoring.SubtestResult(
                subtest: subtest,
                raw: r,
                scaled: scaled
            )
        }
        let avgAll = Double(results.map(\.scaled).reduce(0, +)) / Double(results.count)
        fsiq = WechslerScoring.index(avgScaled: avgAll)
        percentileValue = WechslerScoring.percentile(of: fsiq)
        indexScores = WechslerDomain.allCases.map { domain in
            let related = results.filter { domain.subtests.contains($0.subtest) }
            let avg = Double(related.map(\.scaled).reduce(0, +)) / Double(related.count)
            return (domain, WechslerScoring.index(avgScaled: avg))
        }

        let detail = indexScores.map { "\($0.domain.shortName) \($0.score)" }.joined(separator: " · ")
        RecordStore.append(TestRecord(
            date: Date(),
            testType: .wechsler,
            difficulty: .medium, // 标准流程不分难度
            score: fullScoreItems,
            total: administeredItems,
            iq: fsiq,
            percentile: percentileValue,
            detail: detail,
            age: AgeBand.age
        ))
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
