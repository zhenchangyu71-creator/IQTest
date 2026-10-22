import XCTest
@testable import IQTest

@MainActor
final class WechslerTests: XCTestCase {
    private final class Clock { var time: TimeInterval = 1000 }
    private var savedDefaults: [String: Any] = [:]
    private let keys = ["testTakerAge", "wechslerPracticeStats", "wechslerPracticePercentagesV2"]

    override func setUp() async throws {
        try await super.setUp()
        for key in keys {
            savedDefaults[key] = UserDefaults.standard.object(forKey: key)
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    override func tearDown() async throws {
        for key in keys {
            if let value = savedDefaults[key] { UserDefaults.standard.set(value, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        savedDefaults = [:]
        try await super.tearDown()
    }

    private func model(_ clock: Clock) -> WechslerViewModel {
        WechslerViewModel(now: { clock.time }, saveRecord: { _ in })
    }

    func testEarlyEndPreservesOnlyRecordedItemsAndDoesNotCreateIQ() throws {
        let clock = Clock()
        var records: [TestRecord] = []
        let vm = WechslerViewModel(now: { clock.time }, saveRecord: { records.append($0) })
        vm.start(); begin(vm)
        let prompt = try XCTUnwrap(vm.currentItem?.prompt)
        let displayedOptions = vm.presentedOptions.map(\.text)
        answer(vm, score: 1, clock: clock)
        answer(vm, score: 0, clock: clock)
        vm.endAndSave()
        vm.endAndSave()
        vm.tick()
        XCTAssertEqual(vm.phase, .finished)
        XCTAssertTrue(vm.endedEarly)
        XCTAssertEqual(vm.rawScore, 1)
        XCTAssertEqual(vm.maxRaw, 2)
        XCTAssertNil(vm.iqEstimate)
        XCTAssertEqual(records.count, 1)
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(record.completion, .endedEarly)
        XCTAssertEqual(record.plannedItemCount, 120)
        XCTAssertEqual(record.reviewItems?.count, 2)
        XCTAssertEqual(record.reviewItems?.first?.prompt, prompt)
        XCTAssertEqual(record.reviewItems?.first?.options.map(\.text), displayedOptions)
        let decoded = try JSONDecoder().decode(TestRecord.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(decoded.completion, .endedEarly)
        XCTAssertEqual(decoded.reviewItems?.count, 2)
        XCTAssertFalse(record.reviewItems?.contains { $0.id == "block-03" } ?? true)
    }

    func testExitBeforeAnyScoredAnswerDoesNotCreateAnEmptyRecord() {
        var saved = 0
        let vm = WechslerViewModel(saveRecord: { _ in saved += 1 })
        vm.start()
        vm.endAndSave()
        XCTAssertEqual(vm.phase, .idle)
        XCTAssertEqual(saved, 0)
    }

    func testRecallHistoryPreservesTheOriginalStimulusAndPresentation() throws {
        let clock = Clock()
        var records: [TestRecord] = []
        let vm = WechslerViewModel(now: { clock.time }, saveRecord: { records.append($0) })
        vm.start()
        for _ in 0..<33 { answer(vm, score: 1, clock: clock) }
        XCTAssertEqual(vm.currentItem?.id, "digitspan-10")
        answer(vm, score: 1, clock: clock)
        vm.endAndSave()
        let snapshot = try XCTUnwrap(records.first?.reviewItems?.last)
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
        XCTAssertEqual(encoded["stimulus"] as? String, "9 2 7 4 6")
        XCTAssertEqual(encoded["recallRule"] as? String, "ascending")
        XCTAssertEqual(encoded["displaySeconds"] as? Int, 7)
        XCTAssertEqual(snapshot.correctAnswer, "24679")
        XCTAssertTrue(snapshot.options.isEmpty)
        let decoded = try JSONDecoder().decode(RecordedItem.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(decoded.stimulus, "9 2 7 4 6")
        XCTAssertEqual(decoded.recallRule, .ascending)
        XCTAssertEqual(decoded.displaySeconds, 7)
    }

    func testEndingDuringPendingInterruptionPreservesItsStatus() throws {
        let clock = Clock()
        var records: [TestRecord] = []
        let vm = WechslerViewModel(now: { clock.time }, saveRecord: { records.append($0) })
        vm.start(); begin(vm)
        answer(vm, score: 1, clock: clock)
        vm.setAppActive(false)
        clock.time += 7
        vm.setAppActive(true)
        vm.endAndSave()
        XCTAssertEqual(vm.responses.count, 2)
        XCTAssertEqual(vm.responses.last?.outcome, .interrupted)
        XCTAssertEqual(vm.maxRaw, 1)
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(record.administration?.interruptions.first?.inactiveSeconds, 7)
        XCTAssertEqual(record.reviewItems?.last?.outcome, .interrupted)
    }

    func testInstructionsDoNotExposeScoredAnswersOrStartClock() {
        let clock = Clock()
        let vm = model(clock)
        vm.start()
        XCTAssertEqual(String(describing: vm.phase), "briefing")
        XCTAssertTrue(vm.presentedOptions.isEmpty)
        clock.time += 3600
        vm.tick()
        XCTAssertTrue(vm.responses.isEmpty, "阅读说明和休息不应消耗正式项目时间")
        XCTAssertEqual(vm.itemNumber, 1)
    }

    func testTutorialMustBeCompletedAndDoesNotChangeScore() {
        let clock = Clock()
        let vm = model(clock)
        vm.start()
        vm.beginSubtest()
        XCTAssertEqual(vm.phase, .briefing)
        vm.answerTutorial("不是示例答案")
        vm.beginSubtest()
        XCTAssertEqual(vm.phase, .briefing)
        XCTAssertNotNil(vm.tutorialFeedback)
        vm.answerTutorial(vm.instructions.sample.correctAnswer)
        vm.beginSubtest()
        vm.beginSubtest()
        XCTAssertEqual(vm.phase, .question)
        XCTAssertEqual(vm.completedTutorials, [.block])
        XCTAssertTrue(vm.responses.isEmpty)
        XCTAssertEqual(vm.rawScore, 0)
        answer(vm, score: 1, clock: clock)
        XCTAssertEqual(vm.responses.count, 1)
    }

    func testEachSubtestWaitsForReadinessAndOnlyScoresBankItems() {
        let clock = Clock()
        let vm = model(clock)
        vm.start()
        begin(vm)
        for _ in 0..<12 { answer(vm, score: 0, clock: clock) }
        XCTAssertEqual(vm.phase, .briefing)
        XCTAssertEqual(vm.currentSubtest, .similarities)
        XCTAssertFalse(vm.tutorialPassed)
        XCTAssertNil(vm.tutorialFeedback)
        XCTAssertTrue(vm.presentedOptions.isEmpty)
        XCTAssertEqual(vm.responses.count, 12)
        XCTAssertFalse(vm.responses.contains { $0.itemID.hasPrefix("tutorial-") })
    }

    func testAllTutorialsAreSeparateFromScoredBankAndSolvable() throws {
        let bank = try WechslerLoader.loadValidated()
        for subtest in WechslerSubtest.allCases {
            let instructions = WechslerInstructions.forSubtest(subtest)
            XCTAssertFalse(instructions.guidance.isEmpty)
            XCTAssertFalse(bank.contains { $0.id == instructions.sample.id || $0.prompt == instructions.sample.prompt })
            XCTAssertEqual(instructions.sample.subtest, subtest)
            if instructions.sample.requiresRecall {
                XCTAssertEqual(instructions.sample.recallScore(for: "２ ５ ８"), instructions.sample.maxScore)
                XCTAssertEqual(instructions.sample.recallScore(for: "528"), 0)
            } else {
                XCTAssertEqual(instructions.sample.optionScores.filter { $0 == subtest.maxPointsPerItem }.count, 1)
            }
        }
    }

    func testBackgroundDoesNotAdvanceOrConsumeFollowingItems() throws {
        let clock = Clock()
        let vm = model(clock)
        vm.start(); begin(vm)
        let firstID = try XCTUnwrap(vm.currentItem?.id)
        clock.time += 3
        vm.setAppActive(false)
        clock.time += 3600
        vm.tick()
        XCTAssertEqual(vm.phase, .interrupted)
        XCTAssertEqual(vm.currentItem?.id, firstID)
        XCTAssertTrue(vm.responses.isEmpty)
        vm.resumeAfterInterruption()
        XCTAssertTrue(vm.responses.isEmpty, "后台不能开始后续题目")
        vm.setAppActive(true)
        vm.tick()
        XCTAssertEqual(vm.phase, .interrupted, "返回后需要用户确认继续")
        vm.resumeAfterInterruption()
        XCTAssertEqual(vm.responses.count, 1)
        XCTAssertEqual(vm.responses.first?.outcome, .interrupted)
        XCTAssertNil(vm.responses.first?.answer)
        XCTAssertEqual(vm.currentItem?.id, "block-02")
        XCTAssertEqual(vm.timeRemaining, 45)
        XCTAssertEqual(vm.administration.interruptions.count, 1)
        XCTAssertEqual(vm.administration.interruptions.first?.inactiveSeconds, 3600)
    }

    func testInterruptedItemIsNotTreatedAsWrongOrUsedForIQ() throws {
        let clock = Clock()
        var records: [TestRecord] = []
        let vm = WechslerViewModel(now: { clock.time }, saveRecord: { records.append($0) })
        vm.start(); begin(vm)
        vm.setAppActive(false)
        clock.time += 10
        vm.setAppActive(true)
        vm.resumeAfterInterruption()
        complete(vm, clock: clock, fullScore: true)
        XCTAssertEqual(vm.rawScore, 155)
        XCTAssertEqual(vm.maxRaw, 155)
        XCTAssertEqual(vm.performancePercentage, 100)
        XCTAssertEqual(vm.interruptedCount, 1)
        XCTAssertEqual(vm.result(for: .perceptual).maxRaw, 35)
        XCTAssertNil(vm.iqEstimate)
        XCTAssertTrue(vm.estimationNote?.contains("中断") == true)
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(record.total, 155)
        let roundTrip = try JSONDecoder().decode(TestRecord.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(roundTrip.administration?.protocolVersion, WechslerInstructions.protocolVersion)
        XCTAssertEqual(roundTrip.administration?.completedTutorials.count, 10)
        XCTAssertEqual(roundTrip.administration?.interruptions.first?.itemID, "block-01")
        XCTAssertEqual(roundTrip.responses?.first?.outcome, .interrupted)
    }

    func testInterruptedStimulusIsNotReplayedAndDuplicateEventsAreMerged() {
        let clock = Clock()
        let vm = model(clock)
        vm.start(practice: .digitspan); begin(vm)
        vm.setAppActive(false)
        vm.setAppActive(false)
        clock.time += 7
        vm.setAppActive(true)
        vm.setAppActive(false)
        clock.time += 3
        vm.setAppActive(true)
        vm.resumeAfterInterruption()
        XCTAssertEqual(vm.responses.count, 1)
        XCTAssertEqual(vm.phase, .stimulus)
        XCTAssertEqual(vm.itemNumber, 2)
        XCTAssertEqual(vm.administration.interruptions.count, 1)
        XCTAssertEqual(vm.administration.interruptions.first?.stage, .stimulus)
        XCTAssertEqual(vm.administration.interruptions.first?.inactiveSeconds, 10)
        XCTAssertEqual(vm.responses.first?.elapsedSeconds, 0)
    }

    func testRestOutsideScoredItemsDoesNotFlagInterruption() {
        let clock = Clock()
        let vm = model(clock)
        vm.start()
        vm.setAppActive(false)
        vm.answerTutorial(vm.instructions.sample.correctAnswer)
        vm.beginSubtest()
        XCTAssertEqual(vm.phase, .briefing)
        clock.time += 3600
        vm.setAppActive(true)
        begin(vm)
        XCTAssertEqual(vm.phase, .question)
        XCTAssertTrue(vm.administration.interruptions.isEmpty)
        XCTAssertEqual(vm.timeRemaining, 45)
    }

    func testInterruptedPracticeDoesNotUpdateBestOrCount() {
        let clock = Clock()
        let vm = model(clock)
        vm.start(practice: .block); begin(vm)
        vm.setAppActive(false)
        vm.setAppActive(true)
        vm.resumeAfterInterruption()
        complete(vm, clock: clock, fullScore: true)
        XCTAssertNil(PracticeStore.best(subtest: .block))
        XCTAssertEqual(PracticeStore.count(subtest: .block), 0)
    }

    func testResetClearsPendingInterruptionAndProtocolState() {
        let clock = Clock()
        let vm = model(clock)
        vm.start(); begin(vm)
        vm.setAppActive(false)
        vm.reset()
        vm.setAppActive(true)
        vm.resumeAfterInterruption()
        XCTAssertEqual(vm.phase, .idle)
        XCTAssertTrue(vm.responses.isEmpty)
        XCTAssertTrue(vm.administration.interruptions.isEmpty)
        XCTAssertTrue(vm.completedTutorials.isEmpty)
        vm.start()
        XCTAssertEqual(vm.phase, .briefing)
    }

    func testEveryItemInterruptedLeavesNoScoreableDenominator() {
        let clock = Clock()
        let vm = model(clock)
        vm.start(practice: .block); begin(vm)
        for _ in 0..<3 {
            vm.setAppActive(false)
            vm.setAppActive(true)
            vm.resumeAfterInterruption()
        }
        XCTAssertEqual(vm.phase, .finished)
        XCTAssertEqual(vm.responses.count, 3)
        XCTAssertEqual(vm.interruptedCount, 3)
        XCTAssertEqual(vm.maxRaw, 0)
        XCTAssertTrue(vm.results.allSatisfy { $0.maxRaw == 0 })
        XCTAssertNil(vm.iqEstimate)
        XCTAssertEqual(PracticeStore.count(subtest: .block), 0)
    }

    func testInactiveAtDeadlineDoesNotConvertTimeoutIntoExcludedItem() {
        let clock = Clock()
        let vm = model(clock)
        vm.start(practice: .block); begin(vm)
        clock.time += 45
        vm.setAppActive(false)
        clock.time += 100
        vm.setAppActive(true)
        XCTAssertEqual(vm.phase, .interrupted)
        XCTAssertTrue(vm.responses.isEmpty, "确认前不能呈现后续题")
        vm.resumeAfterInterruption()
        XCTAssertEqual(vm.responses.first?.outcome, .timedOut)
        XCTAssertEqual(vm.responses.first?.elapsedSeconds, 45)
        XCTAssertEqual(vm.interruptedCount, 0)
        XCTAssertEqual(vm.maxRaw, 3)
        XCTAssertTrue(vm.administration.interruptions.isEmpty)
        XCTAssertEqual(vm.itemNumber, 2)
        XCTAssertEqual(vm.timeRemaining, 45)
    }

    private func begin(_ vm: WechslerViewModel) {
        guard vm.phase == .briefing else { return }
        vm.answerTutorial(vm.instructions.sample.correctAnswer)
        vm.beginSubtest()
    }

    private func answer(_ vm: WechslerViewModel, score: Int, clock: Clock) {
        begin(vm)
        if vm.phase == .stimulus {
            clock.time += Double(vm.currentItem?.displaySeconds ?? 4)
            vm.tick()
        }
        guard let item = vm.currentItem else { return XCTFail("题目缺失") }
        if item.requiresRecall {
            vm.submitRecall(score > 0 ? item.correctAnswer : "0", for: item.id)
        } else if let option = vm.presentedOptions.first(where: { $0.score == score }) {
            vm.choose(optionID: option.id, for: item.id)
        } else { XCTFail("缺少对应分值选项") }
    }

    private func complete(_ vm: WechslerViewModel, clock: Clock, fullScore: Bool) {
        for _ in 0..<120 {
            guard vm.phase != .finished else { break }
            answer(vm, score: fullScore ? (vm.currentItem?.maxScore ?? 0) : 0, clock: clock)
        }
        XCTAssertEqual(vm.phase, .finished)
    }

    func testThreeFailuresDoNotSkipUncalibratedItems() {
        let clock = Clock()
        let vm = model(clock)
        vm.start(); begin(vm)
        for _ in 0..<3 { answer(vm, score: 0, clock: clock) }
        XCTAssertEqual(vm.currentSubtest, .block)
        XCTAssertEqual(vm.itemNumber, 4)
        XCTAssertEqual(vm.responses.count, 3)
    }

    func testNoNormedFSIQAndPerfectScoreIs156() {
        let clock = Clock()
        var records: [TestRecord] = []
        AgeBand.age = 12
        let vm = WechslerViewModel(now: { clock.time }, saveRecord: { records.append($0) })
        vm.start(); begin(vm)
        AgeBand.age = 60
        complete(vm, clock: clock, fullScore: true)
        XCTAssertNil(vm.fsiq)
        XCTAssertEqual(vm.rawScore, 156)
        XCTAssertEqual(vm.maxRaw, 156)
        XCTAssertEqual(vm.performancePercentage, 100)
        XCTAssertEqual(vm.responses.count, 120)
        XCTAssertEqual(Set(vm.responses.map(\.itemID)).count, 120)
        XCTAssertEqual(vm.results.count, 10)
        XCTAssertEqual(vm.result(for: .verbal).raw, 72)
        XCTAssertEqual(vm.result(for: .memory).raw, 24)
        XCTAssertEqual(records.count, 1)
        XCTAssertNil(records.first?.iq)
        XCTAssertNil(records.first?.percentile)
        XCTAssertEqual(records.first?.age, 12, "年龄应为开始时的快照")
        XCTAssertEqual(records.first?.responses?.count, 120)
        vm.tick()
        XCTAssertEqual(records.count, 1, "结束后不能重复落库")
    }

    func testCompletedRunSavesAnExplicitlyUncalibratedIQEstimate() throws {
        let clock = Clock()
        var records: [TestRecord] = []
        let vm = WechslerViewModel(now: { clock.time }, saveRecord: { records.append($0) })
        vm.start(); begin(vm)
        complete(vm, clock: clock, fullScore: true)
        let data = try JSONEncoder().encode(XCTUnwrap(records.first))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let estimate = try XCTUnwrap(object["iqEstimate"] as? [String: Any], "完整测验应能保存未校准的 IQ 模型估算")
        XCTAssertNotNil(estimate["value"] as? Int)
        XCTAssertEqual(estimate["calibrationStatus"] as? String, "heuristic")
        XCTAssertEqual(estimate["ageAdjusted"] as? Bool, false)
        XCTAssertNil(object["percentile"], "未校准估算不能产生人群排名")
    }

    func testAllWrongStillCompletes120ItemsWithZeroPoints() {
        let clock = Clock()
        let session = model(clock)
        session.start(); begin(session)
        complete(session, clock: clock, fullScore: false)
        XCTAssertEqual(session.rawScore, 0)
        XCTAssertEqual(session.responses.count, 120)
        XCTAssertEqual(session.performancePercentage, 0)
        XCTAssertNil(session.fsiq)
    }

    func testPartialCreditIsPreservedWithoutAgeBonus() {
        let clock = Clock()
        let vm = model(clock)
        vm.start(); begin(vm)
        for _ in 0..<12 { answer(vm, score: 0, clock: clock) }
        XCTAssertEqual(vm.currentSubtest, .similarities)
        answer(vm, score: 1, clock: clock)
        XCTAssertEqual(vm.rawScore, 1)
        XCTAssertEqual(vm.responses.last?.score, 1)
    }

    func testDuplicateAndForgedOptionDoNotAnswerNextQuestion() throws {
        let vm = model(Clock())
        vm.start(); begin(vm)
        let itemID = try XCTUnwrap(vm.currentItem?.id)
        let option = try XCTUnwrap(vm.presentedOptions.first)
        vm.choose(optionID: UUID(), for: itemID)
        XCTAssertEqual(vm.responses.count, 0)
        vm.choose(optionID: option.id, for: itemID)
        vm.choose(optionID: option.id, for: itemID)
        XCTAssertEqual(vm.responses.count, 1)
        XCTAssertEqual(vm.itemNumber, 2)
    }

    func testDeadlineCheckedBeforeAcceptingAnswer() throws {
        let clock = Clock()
        let session = model(clock)
        session.start(); begin(session)
        let itemID = try XCTUnwrap(session.currentItem?.id)
        let correct = try XCTUnwrap(session.presentedOptions.first { $0.score == 1 })
        clock.time += 45
        session.choose(optionID: correct.id, for: itemID)
        XCTAssertEqual(session.rawScore, 0)
        XCTAssertEqual(session.responses.first?.outcome, .timedOut)
        XCTAssertEqual(session.responses.first?.elapsedSeconds, 45)
        XCTAssertEqual(session.itemNumber, 2)
    }

    func testDelayedStimulusTickDoesNotRestartRecallAllowance() {
        let clock = Clock()
        let vm = model(clock)
        vm.start(practice: .digitspan); begin(vm)
        let displayTime = Double(vm.currentItem?.displaySeconds ?? 4)
        XCTAssertEqual(vm.phase, .stimulus)
        XCTAssertTrue(vm.presentedOptions.isEmpty)
        clock.time += displayTime + 2
        vm.tick()
        XCTAssertEqual(vm.phase, .question)
        XCTAssertEqual(vm.timeRemaining, 13)
        clock.time += 13
        vm.tick()
        XCTAssertEqual(vm.responses.first?.outcome, .timedOut)
        XCTAssertEqual(vm.responses.first?.score, 0)
        XCTAssertEqual(vm.responses.count, 1)
    }

    func testRecallRejectsInvalidInputAndAcceptsOnlyExactSequence() throws {
        let item = try XCTUnwrap(WechslerLoader.load().first { $0.subtest == .digitspan && $0.order == 1 })
        XCTAssertEqual(item.recallScore(for: "482"), 1)
        XCTAssertEqual(item.recallScore(for: "４ ８ ２"), 1)
        XCTAssertEqual(item.recallScore(for: "4 8\n2"), 1)
        XCTAssertEqual(item.recallScore(for: "284"), 0)
        XCTAssertEqual(item.recallScore(for: "0482"), 0)
        XCTAssertNil(item.recallScore(for: ""))
        XCTAssertNil(item.recallScore(for: "4a82"))
        XCTAssertNil(item.recallScore(for: "4-8-2"))
    }

    func testBackwardAscendingAndLeadingZeroRecall() throws {
        let items = try WechslerLoader.loadValidated()
        let backward = try XCTUnwrap(items.first { $0.id == "digitspan-05" })
        XCTAssertEqual(backward.recallScore(for: "6183"), 1)
        XCTAssertEqual(backward.recallScore(for: "3816"), 0)
        let ascending = try XCTUnwrap(items.first { $0.id == "digitspan-10" })
        XCTAssertEqual(ascending.recallScore(for: "24679"), 1)
        XCTAssertEqual(ascending.recallScore(for: "92746"), 0)
        let zero = WechslerItem(id: "zero-fixture", subtest: .digitspan, prompt: "顺序回忆",
                                options: ["0 2 0", "2 0 0"], optionScores: [1, 0], explanation: "020",
                                presentation: "digits", stimulus: "0 2 0", displaySeconds: 4, recallRule: .forward)
        XCTAssertEqual(zero.recallScore(for: "020"), 1)
        XCTAssertEqual(zero.recallScore(for: "20"), 0)
    }

    func testRecallCannotBeAnsweredWithChoiceOrEmptyInput() throws {
        let clock = Clock()
        let vm = model(clock)
        vm.start(practice: .digitspan); begin(vm)
        let id = try XCTUnwrap(vm.currentItem?.id)
        vm.submitRecall("123", for: id)
        XCTAssertTrue(vm.responses.isEmpty, "刺激尚未结束时不能作答")
        clock.time += Double(vm.currentItem?.displaySeconds ?? 4)
        vm.tick()
        vm.choose(optionID: UUID(), for: id)
        vm.submitRecall(" ", for: id)
        vm.submitRecall("abc", for: id)
        XCTAssertTrue(vm.responses.isEmpty)
        vm.submitRecall("0", for: id)
        vm.submitRecall("0", for: id)
        XCTAssertEqual(vm.responses.count, 1)
    }

    func testLoaderKeepsStableIDsAndCompleteExplanations() throws {
        let first = try WechslerLoader.loadValidated()
        let second = try WechslerLoader.loadValidated()
        XCTAssertEqual(first.count, 120)
        XCTAssertEqual(first.map(\.id), second.map(\.id))
        XCTAssertEqual(Set(first.map(\.id)).count, 120)
        XCTAssertTrue(first.allSatisfy { !$0.explanation.isEmpty })
        for subtest in WechslerSubtest.allCases {
            XCTAssertEqual(first.filter { $0.subtest == subtest }.map(\.order), Array(1...12))
        }
    }

    private func corruptedBank(_ mutate: (inout [[String: Any]]) -> Void) throws -> Data {
        let data = try JSONEncoder().encode(WechslerLoader.loadValidated())
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        mutate(&json)
        return try JSONSerialization.data(withJSONObject: json)
    }

    func testMalformedScoringFailsClosed() throws {
        for change: (inout [[String: Any]]) -> Void in [
            { $0[0]["optionScores"] = [1] },
            { $0[0]["optionScores"] = [2, 0, 0, 0] },
            { $0[0]["optionScores"] = [1, 1, 0, 0] },
            { $0[0]["optionScores"] = [-1, 0, 1, 0] },
            { $0[1]["id"] = $0[0]["id"] },
            { $0.removeAll { ($0["subtest"] as? String) == "常识" } }
        ] {
            let data = try corruptedBank(change)
            XCTAssertThrowsError(try WechslerLoader.decode(data))
        }
    }

    func testCorruptDigitStimulusFailsValidation() throws {
        let data = try corruptedBank { rows in
            let index = rows.firstIndex { ($0["id"] as? String) == "digitspan-01" }!
            rows[index]["stimulus"] = "4 X 2"
        }
        XCTAssertThrowsError(try WechslerLoader.decode(data))
    }

    func testWrongRecallKeyFailsValidation() throws {
        let data = try corruptedBank { rows in
            let index = rows.firstIndex { ($0["id"] as? String) == "digitspan-01" }!
            rows[index]["optionScores"] = [0, 1, 0, 0]
        }
        XCTAssertThrowsError(try WechslerLoader.decode(data))
    }

    func testInvalidBankShowsFailureWithoutSavingResult() {
        var saved = 0
        let vm = WechslerViewModel(loader: { _ in [] }, saveRecord: { _ in saved += 1 })
        vm.start(); begin(vm)
        XCTAssertEqual(vm.phase, .failed)
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertEqual(saved, 0)
    }

    func testPracticeZeroIsStoredAsAnAttemptNotMissingData() {
        XCTAssertNil(PracticeStore.best(subtest: .block))
        PracticeStore.recordAttempt(subtest: .block, percentage: 0)
        XCTAssertEqual(PracticeStore.best(subtest: .block), 0)
        XCTAssertEqual(PracticeStore.count(subtest: .block), 1)
        PracticeStore.recordAttempt(subtest: .block, percentage: 67)
        PracticeStore.recordAttempt(subtest: .block, percentage: 33)
        XCTAssertEqual(PracticeStore.best(subtest: .block), 67)
        XCTAssertEqual(PracticeStore.count(subtest: .block), 3)
    }

    func testOldScaledPracticeScoresCannotBecomePercentages() {
        UserDefaults.standard.set(["积木": ["count": 5, "best": 19]], forKey: "wechslerPracticeStats")
        XCTAssertNil(PracticeStore.best(subtest: .block))
        XCTAssertEqual(PracticeStore.count(subtest: .block), 0)
    }

    func testPracticeDrawsFromThreeSectionsAndDoesNotWriteFullHistory() {
        let clock = Clock()
        var saved = 0
        let vm = WechslerViewModel(now: { clock.time }, saveRecord: { _ in saved += 1 })
        vm.start(practice: .vocabulary); begin(vm)
        complete(vm, clock: clock, fullScore: true)
        XCTAssertEqual(vm.responses.count, 3)
        XCTAssertEqual(vm.maxRaw, 6)
        XCTAssertEqual(vm.rawScore, 6)
        let orders = vm.responses.compactMap { vm.item(for: $0)?.order }
        XCTAssertTrue((1...4).contains(orders[0]))
        XCTAssertTrue((5...8).contains(orders[1]))
        XCTAssertTrue((9...12).contains(orders[2]))
        XCTAssertEqual(saved, 0)
        XCTAssertEqual(PracticeStore.best(subtest: .vocabulary), 100)
    }

    func testRawHistoryRoundTripsWithoutFabricatedIQ() throws {
        let response = WechslerResponse(itemID: "block-01", subtest: .block, answer: nil,
                                        score: 0, maxScore: 1, outcome: .timedOut, elapsedSeconds: 45)
        let record = TestRecord(date: Date(timeIntervalSince1970: 0), testType: .wechsler,
                                difficulty: .medium, score: 0, total: 156, iq: nil, percentile: nil,
                                scoringVersion: WechslerLoader.bankVersion, responses: [response])
        let decoded = try JSONDecoder().decode(TestRecord.self, from: JSONEncoder().encode(record))
        XCTAssertNil(decoded.iq)
        XCTAssertNil(decoded.percentile)
        XCTAssertNil(decoded.displayedIQ)
        XCTAssertEqual(decoded.responses?.first?.outcome, .timedOut)
        XCTAssertEqual(decoded.responses?.first?.elapsedSeconds, 45)
        XCTAssertEqual(decoded.scoringVersion, WechslerLoader.bankVersion)
    }

    func testLegacyHistoryRemainsReadableButWechslerEstimateIsNotDisplayed() throws {
        let legacy = #"{"date":0,"testType":"韦氏标准","difficulty":"中级","score":20,"total":30,"iq":130,"percentile":98}"#
        let record = try JSONDecoder().decode(TestRecord.self, from: Data(legacy.utf8))
        XCTAssertEqual(record.iq, 130, "原数据保留以兼容历史")
        XCTAssertNil(record.displayedIQ, "旧韦氏公式不能继续当作 IQ 显示")
        XCTAssertNil(record.scoringVersion)
        XCTAssertNil(record.administration)
        let raven = #"{"date":0,"difficulty":"中级","score":9,"total":12,"iq":115,"percentile":84}"#
        let ravenRecord = try JSONDecoder().decode(TestRecord.self, from: Data(raven.utf8))
        XCTAssertEqual(ravenRecord.testType, .raven)
        XCTAssertEqual(ravenRecord.iq, 115, "旧数据保留，但不当作已校准分数继续显示")
        XCTAssertNil(ravenRecord.displayedIQ)
    }

    func testKnownAmbiguousQuestionsAreRepaired() {
        let items = WechslerLoader.load()
        let block = items.first { $0.subtest == .block && $0.order == 1 }!
        XCTAssertFalse(block.options.contains("一根长条"))
        let puzzle = items.first { $0.subtest == .visualpuzzle && $0.order == 6 }!
        XCTAssertFalse(puzzle.options.contains("扇形"))
        let desert = items.first { $0.subtest == .information && $0.order == 12 }!
        XCTAssertTrue(desert.prompt.contains("热沙漠"))
    }
}
