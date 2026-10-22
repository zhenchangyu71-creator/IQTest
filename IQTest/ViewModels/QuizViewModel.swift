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
    /// 基本信息；测试开始时固定保存，不参与未校准估算。
    @Published var age: Int = AgeBand.age {
        didSet { AgeBand.age = age }
    }
    @Published private(set) var phase: Phase = .ready
    @Published private(set) var questions: [Question] = []
    @Published private(set) var currentIndex = 0
    @Published private(set) var score = 0
    @Published private(set) var answers: [Int?] = []
    @Published private(set) var timeRemaining = Difficulty.medium.secondsPerQuestion
    @Published private(set) var selectedIndex: Int?
    /// 每次呈现都更换，避免旧视图事件提交到下一题或新一轮测试。
    @Published private(set) var questionToken = UUID()

    @Published private(set) var endedEarly = false
    @Published private(set) var bankError: String?
    @Published private(set) var saveError: String?
    private(set) var completedRecord: TestRecord?
    private var recordSaved = false
    private(set) var sessionAge = AgeBand.age
    private(set) var sessionDifficulty = Difficulty.medium
    private(set) var reviewItems: [RecordedItem] = []
    private var questionStarted: TimeInterval = 0
    private var questionDeadline: TimeInterval = 0
    private var feedbackDeadline: TimeInterval?
    private let now: () -> TimeInterval
    private let saveRecord: @MainActor (TestRecord) throws -> Void
    private let loader: () throws -> [Question]

    private nonisolated static let clockOrigin = ContinuousClock.now
    private nonisolated static func continuousTime() -> TimeInterval {
        let elapsed = clockOrigin.duration(to: .now).components
        return Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
    }

    init(loader: @escaping () throws -> [Question] = QuestionLoader.loadValidated,
         now: @escaping () -> TimeInterval = QuizViewModel.continuousTime,
         saveRecord: @escaping @MainActor (TestRecord) throws -> Void = RecordStore.append) {
        self.now = now
        self.saveRecord = saveRecord
        self.loader = loader
    }

    var secondsPerQuestion: Int { difficulty.secondsPerQuestion }

    var currentQuestion: Question? {
        guard currentIndex < questions.count else { return nil }
        return questions[currentIndex]
    }

    var progress: Double {
        guard !questions.isEmpty else { return 0 }
        return Double(currentIndex) / Double(questions.count)
    }

    /// IQ 量尺上的经验模型输出；只有完整作答结果页才展示。
    var estimatedIQ: Int {
        RavenIQEstimate.make(score: score, total: questions.count, difficulty: sessionDifficulty)?.value ?? 100
    }
    var ravenEstimate: RavenIQEstimate? {
        guard phase == .finished, !endedEarly else { return nil }
        return RavenIQEstimate.make(score: score, total: questions.count, difficulty: sessionDifficulty)
    }
    var scoredItemCount: Int { answers.count }

    /// 各分类的答对情况 (分类, 答对数, 总数)
    var categoryBreakdown: [(category: QuestionCategory, correct: Int, total: Int)] {
        var totals: [QuestionCategory: Int] = [:]
        var corrects: [QuestionCategory: Int] = [:]
        for (index, question) in questions.prefix(answers.count).enumerated() {
            totals[question.category, default: 0] += 1
            if let answer = answers[safe: index], answer == question.correctIndex {
                corrects[question.category, default: 0] += 1
            }
        }
        return testType.categories.map { category in
            (category, corrects[category] ?? 0, totals[category] ?? 0)
        }
    }

    // MARK: - 分难度历史最佳

    func bestScore(for level: Difficulty) -> Int {
        let typed = UserDefaults.standard.integer(forKey: Self.bestScoreKey(testType, level))
        if typed > 0 { return typed }
        // 兼容旧版未区分体系的记录
        return UserDefaults.standard.integer(forKey: Self.legacyBestScoreKey(level))
    }

    private static func bestScoreKey(_ type: TestType, _ level: Difficulty) -> String {
        "bestScore_\(type.shortName)_\(level.rawValue)"
    }

    private static func legacyBestScoreKey(_ level: Difficulty) -> String {
        "bestScore_\(level.rawValue)"
    }

    // MARK: - 流程控制

    func start() {
        bankError = nil
        completedRecord = nil
        recordSaved = false
        saveError = nil
        let bank: [Question]
        do {
            bank = try loader()
            try QuestionLoader.validate(bank)
        } catch {
            reset()
            bankError = error.localizedDescription
            return
        }
        let pool = bank.filter {
            $0.testType == testType && $0.difficulty == difficulty
        }
        // 每个分类随机抽取 3 题，共 12 题。优先抽没做过的题：
        // 重复出题会让复测分数混入练习效应，也让多次测量失去意义。
        let exposureKey = ItemExposureStore.bankKey("raven", testType.rawValue, difficulty.rawValue)
        let seen = ItemExposureStore.seen(for: exposureKey)
        questions = testType.categories.flatMap { category -> [Question] in
            let candidates = pool.filter { $0.category == category }
            // 推理题的题号是整数，存进记录时统一转成字符串。
            let unseen = candidates.filter { !seen.contains(String($0.id)) }
            if unseen.isEmpty {
                // 这一类已经全部做过，清空记录重新开始一轮。
                ItemExposureStore.reset(for: exposureKey)
                return candidates.shuffled().prefix(3).map { $0 }
            }
            return unseen.shuffled().prefix(3).map { $0 }
        }.shuffled()
        currentIndex = 0
        score = 0
        answers = []
        reviewItems = []
        endedEarly = false
        sessionAge = age
        sessionDifficulty = difficulty
        beginQuestion()
        phase = .inProgress
    }

    func tick() {
        guard phase == .inProgress else { return }
        let instant = now()
        if let feedbackDeadline {
            if instant >= feedbackDeadline { advance() }
            return
        }
        timeRemaining = max(0, Int(ceil(questionDeadline - instant)))
        if instant >= questionDeadline {
            captureAnswer(nil)
            advance()
        }
    }

    func recordAnswer(_ index: Int, questionToken: UUID) {
        guard phase == .inProgress, questionToken == self.questionToken,
              selectedIndex == nil, let question = currentQuestion,
              question.options.indices.contains(index) else { return }
        let instant = now()
        // 提交时也检查截止时刻，不依赖 Timer 是否已及时刷新。
        guard instant < questionDeadline else {
            captureAnswer(nil)
            advance()
            return
        }
        captureAnswer(index)
        timeRemaining = max(0, Int(ceil(questionDeadline - instant)))
        selectedIndex = index
        feedbackDeadline = instant + 0.8
    }

    private func beginQuestion() {
        questionToken = UUID()
        selectedIndex = nil
        feedbackDeadline = nil
        timeRemaining = sessionDifficulty.secondsPerQuestion
        questionStarted = now()
        questionDeadline = questionStarted + Double(sessionDifficulty.secondsPerQuestion)
    }

    private func advance() {
        selectedIndex = nil
        feedbackDeadline = nil
        if currentIndex == questions.count - 1 {
            finish()
        } else {
            currentIndex += 1
            beginQuestion()
        }
    }

    func reset() {
        phase = .ready
        selectedIndex = nil
        feedbackDeadline = nil
        questionToken = UUID()
        completedRecord = nil
        recordSaved = false
        saveError = nil
    }

    func endAndSave() {
        guard phase == .inProgress else { return }
        if selectedIndex == nil, now() >= questionDeadline { captureAnswer(nil) }
        guard !answers.isEmpty else { reset(); return }
        endedEarly = answers.count < questions.count
        finish()
    }

    private func captureAnswer(_ index: Int?) {
        guard let question = currentQuestion, answers.count == currentIndex else { return }
        answers.append(index)
        if index == question.correctIndex { score += 1 }
        reviewItems.append(.raven(question, selected: index,
                                 elapsedSeconds: min(Double(sessionDifficulty.secondsPerQuestion), max(0, now() - questionStarted))))
    }

    private func finish() {
        guard phase == .inProgress else { return }
        phase = .finished
        selectedIndex = nil
        feedbackDeadline = nil
        // 只记录实际作答过的题：提前结束时未做的题不该被跳过。
        ItemExposureStore.markSeen(reviewItems.map(\.id),
                                   for: ItemExposureStore.bankKey("raven", testType.rawValue,
                                                                  sessionDifficulty.rawValue))
        let record = TestRecord(
            date: Date(), testType: .raven, difficulty: sessionDifficulty,
            score: score, total: answers.count, iq: nil, percentile: nil, age: sessionAge,
            scoringVersion: RavenIQEstimate.currentBankVersion, ravenEstimate: ravenEstimate,
            reviewItems: reviewItems, completion: endedEarly ? .endedEarly : .completed,
            plannedItemCount: questions.count)
        completedRecord = record
        retrySave()
    }

    func retrySave() {
        guard phase == .finished, !recordSaved, let record = completedRecord else { return }
        do {
            try saveRecord(record)
            recordSaved = true
            saveError = nil
            if !endedEarly, score > bestScore(for: sessionDifficulty) {
                UserDefaults.standard.set(score, forKey: Self.bestScoreKey(.raven, sessionDifficulty))
            }
        } catch {
            saveError = "历史保存失败：\(error.localizedDescription)"
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
