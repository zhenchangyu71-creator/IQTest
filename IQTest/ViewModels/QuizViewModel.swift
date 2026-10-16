import Foundation

@MainActor
final class QuizViewModel: ObservableObject {
    enum Phase: Equatable {
        case ready
        case inProgress
        case finished
    }

    @Published var difficulty: Difficulty = .medium {
        didSet { timeRemaining = difficulty.secondsPerQuestion }
    }
    @Published var testType: TestType = .raven
    /// 被试年龄（首页输入，持久化，用于年龄常模校准）
    @Published var age: Int = AgeBand.age {
        didSet { AgeBand.age = age }
    }
    @Published private(set) var phase: Phase = .ready
    @Published private(set) var questions: [Question] = []
    @Published private(set) var currentIndex = 0
    @Published private(set) var score = 0
    @Published private(set) var answers: [Int?] = []
    @Published private(set) var timeRemaining = Difficulty.medium.secondsPerQuestion

    var secondsPerQuestion: Int { difficulty.secondsPerQuestion }

    var currentQuestion: Question? {
        guard currentIndex < questions.count else { return nil }
        return questions[currentIndex]
    }

    var progress: Double {
        guard !questions.isEmpty else { return 0 }
        return Double(currentIndex) / Double(questions.count)
    }

    /// 基于难度与年龄带校准的简化模型：均值 100、标准差 15 的 IQ 分布
    var estimatedIQ: Int {
        let maxScore = max(questions.count, 1)
        let fraction = Double(score) / Double(maxScore)
        let sd: Double = 0.20
        let mean = min(0.95, max(0.05, difficulty.scoreMean + AgeBand.current.ravenMeanOffset))
        let iq = 100 + (fraction - mean) / sd * 15
        return Int(min(145, max(55, iq.rounded())))
    }

    /// 在人群中的百分位（假设 IQ 服从正态分布）
    var percentile: Int {
        let z = Double(estimatedIQ - 100) / 15.0
        let cdf = 0.5 * (1.0 + erf(z / sqrt(2.0)))
        return Int((cdf * 100).rounded())
    }

    /// 各分类的答对情况 (分类, 答对数, 总数)
    var categoryBreakdown: [(category: QuestionCategory, correct: Int, total: Int)] {
        var totals: [QuestionCategory: Int] = [:]
        var corrects: [QuestionCategory: Int] = [:]
        for (index, question) in questions.enumerated() {
            totals[question.category, default: 0] += 1
            if let answer = answers[safe: index], answer == question.correctIndex {
                corrects[question.category, default: 0] += 1
            }
        }
        return testType.categories.map { category in
            (category, corrects[category] ?? 0, totals[category] ?? 0)
        }
    }

    var iqComment: String {
        switch estimatedIQ {
        case ..<70: return "需要进一步提升，多练习会有进步！"
        case 70..<85: return "低于平均水平，加油练习逻辑思维。"
        case 85..<100: return "接近平均水平，再努力一点！"
        case 100..<115: return "处于平均水平以上，表现不错！"
        case 115..<130: return "高于平均水平，思维很敏捷！"
        case 130...: return "非常优秀！属于人群中前 2% 的水平！"
        default: return ""
        }
    }

    // MARK: - 分难度历史最佳

    func bestScore(for level: Difficulty) -> Int {
        let typed = UserDefaults.standard.integer(forKey: Self.bestScoreKey(testType, level))
        if typed > 0 { return typed }
        // 兼容旧版未区分体系的记录
        return UserDefaults.standard.integer(forKey: Self.legacyBestScoreKey(level))
    }

    func bestIQ(for level: Difficulty) -> Int {
        let typed = UserDefaults.standard.integer(forKey: Self.bestIQKey(testType, level))
        if typed > 0 { return typed }
        return UserDefaults.standard.integer(forKey: Self.legacyBestIQKey(level))
    }

    private static func bestScoreKey(_ type: TestType, _ level: Difficulty) -> String {
        "bestScore_\(type.shortName)_\(level.rawValue)"
    }

    private static func bestIQKey(_ type: TestType, _ level: Difficulty) -> String {
        "bestIQ_\(type.shortName)_\(level.rawValue)"
    }

    private static func legacyBestScoreKey(_ level: Difficulty) -> String {
        "bestScore_\(level.rawValue)"
    }

    private static func legacyBestIQKey(_ level: Difficulty) -> String {
        "bestIQ_\(level.rawValue)"
    }

    // MARK: - 流程控制

    func start() {
        let pool = QuestionLoader.load().filter {
            $0.testType == testType && $0.difficulty == difficulty
        }
        // 每个分类随机抽取 3 题，共 12 题
        questions = testType.categories.flatMap { category in
            pool.filter { $0.category == category }.shuffled().prefix(3)
        }.shuffled()
        currentIndex = 0
        score = 0
        answers = []
        timeRemaining = secondsPerQuestion
        phase = .inProgress
    }

    func tick() {
        guard phase == .inProgress else { return }
        timeRemaining -= 1
        if timeRemaining <= 0 {
            recordAnswer(nil) // 超时视为未答
        }
    }

    func recordAnswer(_ index: Int?) {
        guard phase == .inProgress, currentIndex < questions.count else { return }
        answers.append(index)
        if let index, questions[currentIndex].correctIndex == index {
            score += 1
        }
        if currentIndex == questions.count - 1 {
            finish()
        } else {
            currentIndex += 1
            timeRemaining = secondsPerQuestion
        }
    }

    func reset() {
        phase = .ready
    }

    private func finish() {
        phase = .finished
        let level = difficulty
        let record = TestRecord(
            date: Date(),
            testType: testType,
            difficulty: level,
            score: score,
            total: questions.count,
            iq: estimatedIQ,
            percentile: percentile,
            age: age
        )
        RecordStore.append(record)
        if score > bestScore(for: level) {
            UserDefaults.standard.set(score, forKey: Self.bestScoreKey(testType, level))
        }
        if estimatedIQ > bestIQ(for: level) {
            UserDefaults.standard.set(estimatedIQ, forKey: Self.bestIQKey(testType, level))
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
