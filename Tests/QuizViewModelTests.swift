import XCTest
@testable import IQTest

@MainActor
final class QuizViewModelTests: XCTestCase {
    private final class Clock { var time: TimeInterval = 1000 }
    private var records: [TestRecord] = []
    private var savedDefaults: [String: Any] = [:]
    private let keys = ["testTakerAge"] + Difficulty.allCases.flatMap { level in
        ["bestScore_瑞文_\(level.rawValue)", "bestIQ_瑞文_\(level.rawValue)",
         "bestScore_\(level.rawValue)", "bestIQ_\(level.rawValue)"]
    }

    /// 曝光记录存在 UserDefaults 里，会跨测试累积，使抽到的题随执行顺序漂移。
    private let exposureKeys = Difficulty.allCases.map {
        ItemExposureStore.bankKey("raven", TestType.raven.rawValue, $0.rawValue)
    }

    override func setUp() async throws {
        try await super.setUp()
        records = []
        for key in keys {
            savedDefaults[key] = UserDefaults.standard.object(forKey: key)
            UserDefaults.standard.removeObject(forKey: key)
        }
        for key in exposureKeys { ItemExposureStore.reset(for: key) }
    }

    override func tearDown() async throws {
        for key in keys {
            if let value = savedDefaults[key] { UserDefaults.standard.set(value, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        for key in exposureKeys { ItemExposureStore.reset(for: key) }
        savedDefaults = [:]
        try await super.tearDown()
    }

    private func model(_ clock: Clock) -> QuizViewModel {
        QuizViewModel(now: { clock.time }, saveRecord: { self.records.append($0) })
    }

    func testAgeIsRecordedButNeverAdjustsTheEstimate() {
        // 没有年龄常模时，估算不随年龄变化。估算模型本身不接年龄参数，
        // 这条性质由 ageAdjusted 恒为 false 与调用点都不传年龄共同保证
        // （见 RavenIQEstimateTests 与 WechslerIQEstimatorTests）。
        let vm = model(Clock())
        vm.age = 12
        vm.start()
        let answered = vm.scoredItemCount
        vm.age = 60
        XCTAssertEqual(vm.age, 60, "年龄只作记录")
        XCTAssertEqual(vm.scoredItemCount, answered, "改年龄不影响作答与估算")
    }

    func testEarlyEndDuringFeedbackSavesSubmittedAnswerOnceWithoutIQOrBest() throws {
        let clock = Clock()
        let vm = model(clock)
        vm.start()
        vm.recordAnswer(try XCTUnwrap(vm.currentQuestion).correctIndex, questionToken: vm.questionToken)
        vm.endAndSave()
        vm.endAndSave()
        clock.time += 100
        vm.tick()
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(record.completion, .endedEarly)
        XCTAssertEqual(record.score, 1)
        XCTAssertEqual(record.total, 1)
        XCTAssertEqual(record.plannedItemCount, 12)
        XCTAssertEqual(record.reviewItems?.count, 1)
        let decoded = try JSONDecoder().decode(TestRecord.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(decoded.completion, .endedEarly)
        XCTAssertEqual(decoded.plannedItemCount, 12)
        XCTAssertEqual(decoded.reviewItems?.first?.outcome, .answered)
        XCTAssertNil(record.ravenEstimate)
        XCTAssertEqual(vm.bestScore(for: .medium), 0)
    }

    func testEarlyEndAtDeadlineIncludesOnlyCurrentTimeout() throws {
        let clock = Clock()
        let vm = model(clock)
        vm.start()
        clock.time += 45
        vm.endAndSave()
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(record.reviewItems?.count, 1)
        XCTAssertEqual(record.reviewItems?.first?.outcome, .timedOut)
        XCTAssertEqual(record.reviewItems?.first?.elapsedSeconds, 45)
        XCTAssertEqual(record.total, 1)
        XCTAssertNil(record.ravenEstimate)
    }

    func testCompletedRecordSeparatesEstimateAndArchivesPresentedItems() throws {
        let clock = Clock()
        let vm = model(clock)
        vm.start()
        let firstPrompt = try XCTUnwrap(vm.currentQuestion?.prompt)
        for _ in 0..<12 {
            vm.recordAnswer(try XCTUnwrap(vm.currentQuestion).correctIndex, questionToken: vm.questionToken)
            clock.time += 0.81
            vm.tick()
        }
        let record = try XCTUnwrap(records.first)
        XCTAssertNil(record.iq)
        XCTAssertNil(record.percentile)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any])
        XCTAssertNotNil(object["ravenEstimate"])
        let review = try XCTUnwrap(object["reviewItems"] as? [[String: Any]])
        XCTAssertEqual(review.count, 12)
        XCTAssertEqual(review.first?["prompt"] as? String, firstPrompt)
        let decoded = try JSONDecoder().decode(TestRecord.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(decoded.reviewItems?.first?.prompt, firstPrompt)
        XCTAssertEqual(decoded.ravenEstimate?.value, 134)
        XCTAssertFalse(try XCTUnwrap(decoded.ravenEstimate?.ageAdjusted))
    }

    func testRepeatedSubmissionCannotAnswerFollowingQuestion() throws {
        let clock = Clock()
        let vm = model(clock)
        vm.start()
        let question = try XCTUnwrap(vm.currentQuestion)
        let token = vm.questionToken

        vm.recordAnswer(question.correctIndex, questionToken: token)
        vm.recordAnswer(question.correctIndex, questionToken: token)

        XCTAssertEqual(vm.answers.count, 1, "一次点击的重复提交只能记录一个答案")
        XCTAssertEqual(vm.currentIndex, 0, "答案应先锁定并展示反馈，之后才换题")
        XCTAssertEqual(vm.score, 1)
        XCTAssertEqual(vm.selectedIndex, question.correctIndex)

        clock.time += 0.81
        vm.tick()
        XCTAssertEqual(vm.currentIndex, 1)
        XCTAssertNil(vm.selectedIndex)
        XCTAssertEqual(vm.answers.count, 1)
    }

    func testLastMomentAnswerRemainsCorrectWhileFeedbackCrossesDeadline() throws {
        let clock = Clock()
        let vm = model(clock)
        vm.start()
        let question = try XCTUnwrap(vm.currentQuestion)
        clock.time += 44.9
        vm.recordAnswer(question.correctIndex, questionToken: vm.questionToken)

        XCTAssertEqual(vm.score, 1, "点击时立即计分")
        XCTAssertEqual(vm.timeRemaining, 1)
        clock.time += 0.2
        vm.tick()
        XCTAssertEqual(vm.currentIndex, 0, "展示反馈期间不能超时换题")
        XCTAssertEqual(vm.answers, [question.correctIndex])
        clock.time += 0.61
        vm.tick()
        XCTAssertEqual(vm.currentIndex, 1)
        XCTAssertEqual(vm.timeRemaining, 45, "下一题从呈现时获得完整作答时间")
        XCTAssertEqual(vm.score, 1)
    }

    func testAnswerAtOrAfterDeadlineTimesOutWithoutWaitingForTimer() throws {
        for elapsed in [45.0, 45.001, 500.0] {
            let clock = Clock()
            let vm = model(clock)
            vm.start()
            let question = try XCTUnwrap(vm.currentQuestion)
            clock.time += elapsed
            vm.recordAnswer(question.correctIndex, questionToken: vm.questionToken)

            XCTAssertEqual(vm.score, 0)
            XCTAssertEqual(vm.answers.count, 1)
            XCTAssertNil(vm.answers[0])
            XCTAssertEqual(vm.currentIndex, 1)
            XCTAssertEqual(vm.timeRemaining, 45)
            XCTAssertNil(vm.selectedIndex)
        }
    }

    func testCountdownUsesElapsedTimeInsteadOfNumberOfTimerCallbacks() {
        let clock = Clock()
        let vm = model(clock)
        vm.start()
        clock.time += 11.4
        vm.tick()
        XCTAssertEqual(vm.timeRemaining, 34)
        vm.tick()
        XCTAssertEqual(vm.timeRemaining, 34, "重复刷新不能多扣时间")
        clock.time = 1045
        vm.tick()
        XCTAssertEqual(vm.answers.count, 1)
        XCTAssertNil(vm.answers[0])
        XCTAssertEqual(vm.currentIndex, 1)
    }

    func testDelayedTimerOnlyExpiresPresentedQuestion() {
        let clock = Clock()
        let vm = model(clock)
        vm.start()
        clock.time += 3600
        vm.tick()
        vm.tick()
        XCTAssertEqual(vm.answers.count, 1, "延迟刷新不能消耗尚未呈现的题目")
        XCTAssertNil(vm.answers[0])
        XCTAssertEqual(vm.currentIndex, 1)
        XCTAssertEqual(vm.timeRemaining, 45)
    }

    func testSubmissionFromPreviousQuestionCannotAnswerNewQuestion() throws {
        let clock = Clock()
        let vm = model(clock)
        vm.start()
        let token = vm.questionToken
        vm.recordAnswer(try XCTUnwrap(vm.currentQuestion).correctIndex, questionToken: token)
        clock.time += 0.81
        vm.tick()
        let next = try XCTUnwrap(vm.currentQuestion)
        vm.recordAnswer(next.correctIndex, questionToken: token)

        XCTAssertEqual(vm.answers.count, 1)
        XCTAssertEqual(vm.score, 1)
        XCTAssertEqual(vm.currentIndex, 1)
        XCTAssertNil(vm.selectedIndex)
        vm.recordAnswer(next.correctIndex, questionToken: vm.questionToken)
        XCTAssertEqual(vm.score, 2)
    }

    func testSubmissionFromTimedOutQuestionCannotAnswerNewQuestion() throws {
        let clock = Clock()
        let vm = model(clock)
        vm.start()
        let token = vm.questionToken
        let oldAnswer = try XCTUnwrap(vm.currentQuestion).correctIndex
        clock.time += 45
        vm.tick()
        vm.recordAnswer(oldAnswer, questionToken: token)

        XCTAssertEqual(vm.answers.count, 1)
        XCTAssertNil(vm.answers[0])
        XCTAssertEqual(vm.score, 0)
        XCTAssertEqual(vm.currentIndex, 1)
    }

    func testRestartRejectsSubmissionsFromPreviousRun() throws {
        let clock = Clock()
        let vm = model(clock)
        vm.start()
        let token = vm.questionToken
        vm.start()
        vm.recordAnswer(try XCTUnwrap(vm.currentQuestion).correctIndex, questionToken: token)

        XCTAssertTrue(vm.answers.isEmpty)
        XCTAssertEqual(vm.score, 0)
        XCTAssertEqual(vm.currentIndex, 0)
        XCTAssertNil(vm.selectedIndex)
    }

    func testResetDuringFeedbackCancelsPendingAdvance() throws {
        let clock = Clock()
        let vm = model(clock)
        vm.start()
        let token = vm.questionToken
        vm.recordAnswer(try XCTUnwrap(vm.currentQuestion).correctIndex, questionToken: token)
        vm.reset()
        clock.time += 100
        vm.tick()

        XCTAssertEqual(vm.phase, .ready)
        XCTAssertNil(vm.selectedIndex)
        XCTAssertTrue(records.isEmpty)
        vm.start()
        vm.tick()
        vm.recordAnswer(0, questionToken: token)
        XCTAssertEqual(vm.currentIndex, 0)
        XCTAssertTrue(vm.answers.isEmpty)
        XCTAssertEqual(vm.timeRemaining, 45)
    }

    func testInvalidOptionDoesNotEnterResultsOrAdvance() throws {
        let clock = Clock()
        let vm = model(clock)
        vm.start()
        let question = try XCTUnwrap(vm.currentQuestion)
        vm.recordAnswer(-1, questionToken: vm.questionToken)
        vm.recordAnswer(question.options.count, questionToken: vm.questionToken)

        XCTAssertTrue(vm.answers.isEmpty)
        XCTAssertNil(vm.selectedIndex)
        XCTAssertEqual(vm.currentIndex, 0)
        vm.recordAnswer(question.correctIndex, questionToken: vm.questionToken)
        XCTAssertEqual(vm.score, 1)
    }

    func testCompletedRunSavesExactlyOneRecordAfterFinalFeedback() throws {
        let clock = Clock()
        let vm = model(clock)
        vm.start()
        XCTAssertEqual(vm.questions.count, 12)
        for _ in 0..<12 {
            let question = try XCTUnwrap(vm.currentQuestion)
            vm.recordAnswer(question.correctIndex, questionToken: vm.questionToken)
            XCTAssertTrue(records.isEmpty, "最后一题反馈结束后才进入结果页和保存")
            clock.time += 0.81
            vm.tick()
        }

        XCTAssertEqual(vm.phase, .finished)
        XCTAssertEqual(vm.answers.count, 12)
        XCTAssertEqual(vm.score, 12)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.score, 12)
        XCTAssertEqual(records.first?.total, 12)
        XCTAssertEqual(records.first?.testType, .raven)
        XCTAssertEqual(vm.bestScore(for: .medium), 12)
        vm.recordAnswer(0, questionToken: vm.questionToken)
        clock.time += 100
        vm.tick()
        XCTAssertEqual(records.count, 1)
    }

    func testAllTimeoutsCompleteOnceWithoutFeedbackOrScore() {
        let clock = Clock()
        let vm = model(clock)
        vm.start()
        for _ in 0..<12 {
            clock.time += 45
            vm.tick()
        }

        XCTAssertEqual(vm.phase, .finished)
        XCTAssertEqual(vm.answers.count, 12)
        XCTAssertTrue(vm.answers.allSatisfy { $0 == nil })
        XCTAssertEqual(vm.score, 0)
        XCTAssertNil(vm.selectedIndex)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.score, 0)
        vm.tick()
        XCTAssertEqual(records.count, 1)
    }
}
