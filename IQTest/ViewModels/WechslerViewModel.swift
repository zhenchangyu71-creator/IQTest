import Foundation

/// 共享答题流程。完整练习不套用未验证的停测或年龄加分规则。
@MainActor
class WechslerViewModel: ObservableObject {
    enum Phase: Equatable { case idle, briefing, stimulus, question, interrupted, finished, failed }
    struct Option: Identifiable {
        let id = UUID()
        let text: String
        let score: Int
    }

    /// 完整练习时每个分测验抽多少题。题池比这个大，抽题时优先选没做过的。
    static let itemsPerSubtest = 12

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var currentSubtest: WechslerSubtest = .block
    @Published private(set) var itemNumber = 0
    @Published private(set) var itemsInSubtest = 0
    @Published private(set) var stimulusRemaining = 0
    @Published private(set) var timeRemaining = 0
    @Published private(set) var presentedOptions: [Option] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var tutorialPassed = false
    @Published private(set) var tutorialFeedback: String?
    private(set) var completedTutorials: [WechslerSubtest] = []
    var instructions: WechslerInstructions { .forSubtest(currentSubtest) }
    private(set) var responses: [WechslerResponse] = []
    private(set) var reviewItems: [RecordedItem] = []
    private(set) var endedEarly = false
    private(set) var results: [WechslerScoring.SubtestResult] = []
    private(set) var sessionAge = AgeBand.age
    private(set) var sessionQuestionSet: WechslerQuestionSet?
    @Published private(set) var saveError: String?
    private(set) var completedRecord: TestRecord?
    private var recordSaved = false
    private(set) var hasPriorPractice = false
    private(set) var iqEstimate: WechslerIQEstimate?
    /// 韦氏风格的量表分剖面（尺度分 / 指数分 / 全量表分），未经人群常模校准。
    private(set) var profile: WechslerProfile?
    private(set) var estimationNote: String?
    /// 正式 FSIQ 始终不可用；实验性估算单独保存。
    var fsiq: Int? { nil }
    var rawScore: Int { responses.reduce(0) { $0 + $1.score } }
    var maxRaw: Int {
        let excluded = Set(responses.filter { $0.outcome == .interrupted }.map(\.itemID))
        let recorded = Set(responses.map(\.itemID))
        return items.filter { !excluded.contains($0.id) && (!endedEarly || recorded.contains($0.id)) }.reduce(0) { $0 + $1.maxScore }
    }
    var performancePercentage: Int { WechslerScoring.percentage(raw: rawScore, maxRaw: maxRaw) }
    var timedOutCount: Int { responses.filter { $0.outcome == .timedOut }.count }
    var interruptedCount: Int { responses.filter { $0.outcome == .interrupted }.count }
    var interruptedItemExpired: Bool { pendingInterruption?.deadlineExpired == true }
    var administration: WechslerAdministration {
        WechslerAdministration(protocolVersion: WechslerInstructions.protocolVersion,
                               completedTutorials: completedTutorials, hasPriorExposure: hasPriorPractice,
                               interruptions: interruptions)
    }
    var itemCount: Int { items.count }
    var currentItem: WechslerItem? { items.indices.contains(cursor) ? items[cursor] : nil }
    var totalProgress: Double { items.isEmpty ? 0 : Double(responses.count) / Double(items.count) }

    /// 本轮要做的题目。测试需要读出题号以验证抽题轮换，因此保持只读公开。
    private(set) var items: [WechslerItem] = []
    private var cursor = 0
    private var questionStarted: TimeInterval = 0
    private var stimulusDeadline: TimeInterval = 0
    private var questionDeadline: TimeInterval = 0
    private var practiceSubtest: WechslerSubtest?
    private var appIsActive = true
    private var interruptions: [WechslerAdministration.Interruption] = []
    private struct PendingInterruption {
        let itemID: String
        let stage: WechslerAdministration.Interruption.Stage
        let elapsedSeconds: Double
        let deadlineExpired: Bool
        var inactiveSeconds: Double = 0
        var inactiveSince: TimeInterval?
    }
    private var pendingInterruption: PendingInterruption?
    private var optionsForArchive: [RecordedItem.Option] = []
    private let loader: (WechslerQuestionSet) throws -> [WechslerItem]
    private let now: () -> TimeInterval
    private let saveRecord: @MainActor (TestRecord) throws -> Void

    private nonisolated static let clockOrigin = ContinuousClock.now
    private nonisolated static func continuousTime() -> TimeInterval {
        let elapsed = clockOrigin.duration(to: .now).components
        return Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
    }

    init(loader: @escaping (WechslerQuestionSet) throws -> [WechslerItem] = WechslerLoader.loadValidated,
         now: @escaping () -> TimeInterval = WechslerViewModel.continuousTime,
         saveRecord: @escaping @MainActor (TestRecord) throws -> Void = RecordStore.append) {
        self.loader = loader
        self.now = now
        self.saveRecord = saveRecord
    }

    func start(practice subtest: WechslerSubtest? = nil, questionSet: WechslerQuestionSet = .a) {
        reset()
        do {
            let sets = subtest == nil ? [questionSet] : WechslerQuestionSet.allCases
            let loaded = try sets.flatMap { try loader($0) }
            try WechslerLoader.validate(loaded)
            practiceSubtest = subtest
            sessionQuestionSet = subtest == nil ? questionSet : nil
            if let subtest {
                let pool = loaded.filter { $0.subtest == subtest }.sorted { $0.order < $1.order }
                // 按实际题量分为三段；不将文件位置宣称为已校准的难度。
                // 题库里存在内容完全相同的题，且重复对分布在不同段里
                // （词汇 13/25、常识 14/26…），两段可能取到同一道题——
                // 一次练习里出现两道一样的题是用户直接看得见的缺陷。
                // 单项练习不记曝光，所以这里只能靠当次去重来避免。
                var pickedContent = Set<String>()
                var picked: [WechslerItem] = []
                for segment in 0..<3 {
                    let lower = segment * pool.count / 3
                    let upper = (segment + 1) * pool.count / 3
                    let segmentItems = Array(pool[lower..<upper])
                    let fresh = segmentItems.filter { !pickedContent.contains($0.contentKey) }
                    guard let item = (fresh.isEmpty ? segmentItems : fresh).randomElement() else { continue }
                    pickedContent.insert(item.contentKey)
                    picked.append(item)
                }
                items = picked
            } else {
                // 每个分测验从题池中抽取固定题量，优先没做过的题：
                // 整轮都做同一批题会让第二次测试必然重复，练习效应直接混入复测分数。
                let exposureKey = ItemExposureStore.bankKey("wechsler", questionSet.rawValue)
                let seen = ItemExposureStore.seen(for: exposureKey)
                // 题库里存在内容完全相同的题——扩充时把原有题又追加了一遍，
                // 词汇、常识、符号编码三个分测验各有 12 对。
                // 「做没做过」与「一轮内不重复」都按内容判断而不是按题号：
                // 按题号判断会让同一轮出现两道一样的题（约一半的轮次），
                // 也会让复测时同内容的另一份被当成「新题」抽到。
                let contentById = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0.contentKey) })
                let seenContent = Set(seen.compactMap { contentById[$0] })
                items = WechslerSubtest.allCases.flatMap { sub -> [WechslerItem] in
                    let pool = loaded.filter { $0.subtest == sub }.sorted { $0.order < $1.order }
                    let unseen = pool.filter { !seenContent.contains(contentById[$0.id] ?? "") }
                    // 同一轮里不出现内容相同的两道题。
                    var picked: [WechslerItem] = []
                    var pickedContent = Set<String>()
                    for item in unseen {
                        let key = contentById[item.id] ?? ""
                        guard pickedContent.insert(key).inserted else { continue }
                        picked.append(item)
                        if picked.count == WechslerViewModel.itemsPerSubtest { break }
                    }
                    if picked.count < WechslerViewModel.itemsPerSubtest {
                        // 未做过的题不够时用做过的题补足，保证每轮题量恒定。
                        // 否则同一轮的分母会随已做题数缩水，不同轮次的得分率无法比较。
                        let rest = pool.filter { !pickedContent.contains(contentById[$0.id] ?? "") }
                        for item in rest {
                            let key = contentById[item.id] ?? ""
                            guard pickedContent.insert(key).inserted else { continue }
                            picked.append(item)
                            if picked.count == WechslerViewModel.itemsPerSubtest { break }
                        }
                    }
                    return picked
                }
            }
            sessionAge = AgeBand.age
            hasPriorPractice = WechslerSubtest.allCases.contains { PracticeStore.count(subtest: $0) > 0 }
                || ((try? RecordStore.load())?.contains { $0.testType == .wechsler } ?? false)
            presentCurrentItem()
        } catch {
            errorMessage = error.localizedDescription
            phase = .failed
        }
    }

    func reset() {
        phase = .idle
        items = []
        cursor = 0
        responses = []
        reviewItems = []
        endedEarly = false
        results = []
        iqEstimate = nil
        profile = nil
        estimationNote = nil
        presentedOptions = []
        optionsForArchive = []
        stimulusRemaining = 0
        timeRemaining = 0
        errorMessage = nil
        tutorialPassed = false
        tutorialFeedback = nil
        completedTutorials = []
        interruptions = []
        pendingInterruption = nil
        hasPriorPractice = false
        sessionQuestionSet = nil
        saveError = nil
        completedRecord = nil
        recordSaved = false
    }

    func answerTutorial(_ answer: String) {
        guard phase == .briefing, appIsActive, !tutorialPassed else { return }
        let sample = instructions.sample
        let correct = sample.requiresRecall
            ? sample.recallScore(for: answer) == sample.maxScore
            : answer == sample.correctAnswer
        tutorialPassed = correct
        tutorialFeedback = (correct ? "示例已完成。" : "可以再试一次。") + sample.explanation
    }

    func beginSubtest() {
        guard phase == .briefing, tutorialPassed, appIsActive else { return }
        completedTutorials.append(currentSubtest)
        presentCurrentItem()
    }

    /// 失去前台时立即遮住项目并冻结推进；后台时长只记录，不补偿作答时间。
    func setAppActive(_ active: Bool) {
        guard active != appIsActive else { return }
        appIsActive = active
        let instant = now()
        if active {
            if let since = pendingInterruption?.inactiveSince {
                pendingInterruption?.inactiveSeconds += max(0, instant - since)
                pendingInterruption?.inactiveSince = nil
            }
        } else if phase == .stimulus || phase == .question, let item = currentItem {
            pendingInterruption = PendingInterruption(
                itemID: item.id, stage: phase == .stimulus ? .stimulus : .question,
                elapsedSeconds: min(Double(item.subtest.timeLimit), max(0, instant - questionStarted)),
                deadlineExpired: instant >= questionDeadline,
                inactiveSince: instant)
            presentedOptions = []
            phase = .interrupted
        } else if phase == .interrupted {
            pendingInterruption?.inactiveSince = instant
        }
    }

    func resumeAfterInterruption() {
        guard appIsActive, phase == .interrupted, let pending = pendingInterruption else { return }
        if !pending.deadlineExpired {
            interruptions.append(.init(itemID: pending.itemID, stage: pending.stage,
                                       inactiveSeconds: pending.inactiveSeconds))
        }
        pendingInterruption = nil
        // 已曝光的项目不重播、不猜测缺失得分，后续题从确认继续时开始。
        record(answer: nil, score: 0, outcome: pending.deadlineExpired ? .timedOut : .interrupted,
               elapsedSeconds: pending.elapsedSeconds)
    }

    /// 基于单调时钟的截止时刻计时；中断交给独立阶段处理。
    func tick() {
        guard appIsActive, phase == .stimulus || phase == .question else { return }
        let instant = now()
        if instant >= questionDeadline {
            record(answer: nil, score: 0, outcome: .timedOut)
        } else if phase == .stimulus {
            stimulusRemaining = max(0, Int(ceil(stimulusDeadline - instant)))
            if instant >= stimulusDeadline {
                timeRemaining = max(0, Int(ceil(questionDeadline - instant)))
                phase = .question
            }
        } else {
            timeRemaining = max(0, Int(ceil(questionDeadline - instant)))
        }
    }

    func choose(optionID: UUID, for itemID: String) {
        guard phase == .question, let item = currentItem, item.id == itemID,
              !item.requiresRecall, let option = presentedOptions.first(where: { $0.id == optionID }) else { return }
        guard now() < questionDeadline else { tick(); return }
        record(answer: option.text, score: option.score, outcome: .answered)
    }

    func submitRecall(_ answer: String, for itemID: String) {
        guard phase == .question, let item = currentItem, item.id == itemID,
              let score = item.recallScore(for: answer) else { return }
        guard now() < questionDeadline else { tick(); return }
        record(answer: answer, score: score, outcome: .answered)
    }

    func result(for domain: WechslerDomain) -> (raw: Int, maxRaw: Int) {
        let relevant = results.filter { $0.subtest.domain == domain }
        return (relevant.reduce(0) { $0 + $1.raw }, relevant.reduce(0) { $0 + $1.maxRaw })
    }

    func item(for response: WechslerResponse) -> WechslerItem? {
        items.first { $0.id == response.itemID }
    }

    private func presentCurrentItem() {
        guard let item = currentItem else { finish(); return }
        currentSubtest = item.subtest
        itemNumber = items.prefix(cursor + 1).filter { $0.subtest == item.subtest }.count
        itemsInSubtest = items.filter { $0.subtest == item.subtest }.count
        if !completedTutorials.contains(item.subtest) {
            presentedOptions = []
            timeRemaining = 0
            stimulusRemaining = 0
            tutorialPassed = false
            tutorialFeedback = nil
            phase = .briefing
            return
        }
        presentedOptions = item.requiresRecall ? [] : zip(item.options, item.optionScores)
            .map { Option(text: $0.0, score: $0.1) }.shuffled()
        optionsForArchive = presentedOptions.map { .init(text: $0.text, score: $0.score) }
        let instant = now()
        stimulusDeadline = instant + Double(item.requiresRecall ? (item.displaySeconds ?? 4) : 0)
        questionStarted = stimulusDeadline
        questionDeadline = questionStarted + Double(item.subtest.timeLimit)
        stimulusRemaining = item.requiresRecall ? (item.displaySeconds ?? 4) : 0
        timeRemaining = item.subtest.timeLimit
        phase = item.requiresRecall ? .stimulus : .question
    }

    private func captureResponse(answer: String?, score: Int, outcome: WechslerResponse.Outcome,
                                 elapsedSeconds: Double? = nil) {
        guard let item = currentItem else { return }
        let elapsed = elapsedSeconds ?? min(Double(item.subtest.timeLimit), max(0, now() - questionStarted))
        responses.append(WechslerResponse(itemID: item.id, subtest: item.subtest, answer: answer,
                                          score: score, maxScore: item.maxScore, outcome: outcome, elapsedSeconds: elapsed))
        let recordedOutcome: RecordedItem.Outcome
        switch outcome {
        case .answered: recordedOutcome = .answered
        case .timedOut: recordedOutcome = .timedOut
        case .interrupted: recordedOutcome = .interrupted
        }
        reviewItems.append(RecordedItem(id: item.id, group: item.subtest.rawValue, prompt: item.prompt,
                                         stimulus: item.stimulus, recallRule: item.recallRule,
                                         displaySeconds: item.requiresRecall ? (item.displaySeconds ?? 4) : nil,
                                         options: optionsForArchive,
                                         answer: answer, correctAnswer: item.expectedRecall ?? item.correctAnswer,
                                         explanation: item.explanation, score: score, maxScore: item.maxScore,
                                         outcome: recordedOutcome, elapsedSeconds: elapsed))
    }

    private func record(answer: String?, score: Int, outcome: WechslerResponse.Outcome,
                        elapsedSeconds: Double? = nil) {
        captureResponse(answer: answer, score: score, outcome: outcome, elapsedSeconds: elapsedSeconds)
        cursor += 1
        presentCurrentItem()
    }

    func endAndSave() {
        guard [.briefing, .stimulus, .question, .interrupted].contains(phase) else { return }
        if let pending = pendingInterruption {
            let inactive = pending.inactiveSeconds + (pending.inactiveSince.map { max(0, now() - $0) } ?? 0)
            if !pending.deadlineExpired {
                interruptions.append(.init(itemID: pending.itemID, stage: pending.stage, inactiveSeconds: inactive))
            }
            captureResponse(answer: nil, score: 0, outcome: pending.deadlineExpired ? .timedOut : .interrupted,
                            elapsedSeconds: pending.elapsedSeconds)
            pendingInterruption = nil
        } else if (phase == .stimulus || phase == .question), now() >= questionDeadline {
            captureResponse(answer: nil, score: 0, outcome: .timedOut)
        }
        guard !responses.isEmpty else { reset(); return }
        finish(endedEarly: responses.count < items.count)
    }

    private func finish(endedEarly: Bool = false) {
        guard !items.isEmpty, endedEarly || responses.count == items.count else { return }
        self.endedEarly = endedEarly
        // 只记录实际作答过的题：提前结束时未做的题不该被跳过。
        if let set = sessionQuestionSet {
            ItemExposureStore.markSeen(responses.map(\.itemID),
                                       for: ItemExposureStore.bankKey("wechsler", set.rawValue))
        }
        let answeredIDs = Set(responses.map(\.itemID))
        let scoredItems = endedEarly ? items.filter { answeredIDs.contains($0.id) } : items
        results = WechslerScoring.results(items: scoredItems, responses: responses).filter { $0.total > 0 }
        if let practiceSubtest {
            if interruptedCount == 0 && !endedEarly {
                PracticeStore.recordAttempt(subtest: practiceSubtest, percentage: performancePercentage)
            }
        } else {
            if endedEarly {
                estimationNote = "本次提前结束，仅报告已答题成绩，不生成 IQ 估算。"
            } else {
                do {
                    let model = try WechslerIQModel.load(sessionQuestionSet ?? .a)
                    iqEstimate = try WechslerIQEstimator.estimate(items: items, responses: responses, model: model)
                    let ability = try WechslerIQEstimator.ability(items: items, responses: responses, model: model)
                    profile = WechslerProfileScorer.make(ability: ability, flags: iqEstimate?.flags ?? [],
                                                         modelVersion: model.version, bankVersion: model.bankVersion)
                } catch {
                    estimationNote = error.localizedDescription
                }
            }
            let detail = WechslerDomain.allCases.map { domain in
                let value = result(for: domain)
                return "\(domain.shortName) \(value.raw)/\(value.maxRaw)"
            }.joined(separator: " · ")
            completedRecord = TestRecord(date: Date(), testType: .wechsler, difficulty: .medium,
                                  score: rawScore, total: maxRaw, iq: nil, percentile: nil,
                                  detail: detail, age: sessionAge,
                                  scoringVersion: WechslerLoader.bankVersion, responses: responses, iqEstimate: iqEstimate,
                                  wechslerProfile: profile,
                                  administration: administration, reviewItems: reviewItems,
                                  completion: endedEarly ? .endedEarly : .completed, plannedItemCount: items.count,
                                  questionSet: sessionQuestionSet)
        }
        presentedOptions = []
        phase = .finished
        retrySave()
    }

    func retrySave() {
        guard phase == .finished, !recordSaved, let record = completedRecord else { return }
        do {
            try saveRecord(record)
            recordSaved = true
            saveError = nil
        } catch {
            saveError = "历史保存失败：\(error.localizedDescription)"
        }
    }
}
