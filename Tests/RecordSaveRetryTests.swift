import XCTest
@testable import IQTest

@MainActor
final class RecordSaveRetryTests: XCTestCase {
    private enum Failure: Error { case disk }

    /// 曝光记录存在 UserDefaults 里，会跨测试累积，使抽到的题随执行顺序漂移。
    private let exposureKeys = [
        ItemExposureStore.bankKey("wechsler", WechslerQuestionSet.a.rawValue),
        ItemExposureStore.bankKey("wechsler", WechslerQuestionSet.b.rawValue)
    ]

    override func setUp() {
        super.setUp()
        for key in exposureKeys { ItemExposureStore.reset(for: key) }
    }

    override func tearDown() {
        for key in exposureKeys { ItemExposureStore.reset(for: key) }
        super.tearDown()
    }

    func testRavenRetryPreservesOneFrozenRecordWithoutRescoring() throws {
        var attempts: [TestRecord] = []
        let vm = QuizViewModel(saveRecord: { record in
            attempts.append(record)
            if attempts.count == 1 { throw Failure.disk }
        })
        vm.start()
        vm.recordAnswer(try XCTUnwrap(vm.currentQuestion).correctIndex, questionToken: vm.questionToken)
        vm.endAndSave()
        XCTAssertEqual(vm.phase, .finished)
        XCTAssertNotNil(vm.saveError)
        let first = try XCTUnwrap(attempts.first)
        vm.retrySave()
        vm.retrySave()
        XCTAssertNil(vm.saveError)
        XCTAssertEqual(attempts.count, 2)
        XCTAssertEqual(attempts[1].id, first.id)
        XCTAssertEqual(attempts[1].date, first.date)
        XCTAssertEqual(attempts[1].reviewItems?.count, 1)
        XCTAssertEqual(vm.score, 1)
    }

    func testWechslerRetryPreservesQuestionSetAndPartialAnswers() throws {
        var attempts: [TestRecord] = []
        let vm = WechslerViewModel(saveRecord: { record in
            attempts.append(record)
            if attempts.count == 1 { throw Failure.disk }
        })
        vm.start(questionSet: .b)
        vm.answerTutorial(vm.instructions.sample.correctAnswer)
        vm.beginSubtest()
        vm.choose(optionID: try XCTUnwrap(vm.presentedOptions.first).id, for: try XCTUnwrap(vm.currentItem).id)
        vm.endAndSave()
        XCTAssertNotNil(vm.saveError)
        vm.retrySave()
        vm.retrySave()
        XCTAssertNil(vm.saveError)
        XCTAssertEqual(attempts.count, 2)
        XCTAssertEqual(attempts[0].id, attempts[1].id)
        XCTAssertEqual(attempts[1].questionSet, .b)
        XCTAssertEqual(attempts[1].reviewItems?.count, 1)
        XCTAssertEqual(attempts[1].completion, .endedEarly)
    }

    func testFullRavenFailureDoesNotUpdateBestUntilRetrySucceeds() throws {
        let keys = ["bestScore_瑞文_中级", "bestScore_中级"]
        let previous = keys.map { UserDefaults.standard.object(forKey: $0) }
        for key in keys { UserDefaults.standard.removeObject(forKey: key) }
        defer {
            for (key, value) in zip(keys, previous) {
                if let value { UserDefaults.standard.set(value, forKey: key) }
                else { UserDefaults.standard.removeObject(forKey: key) }
            }
        }
        var time: TimeInterval = 1000
        var attempts = 0
        let vm = QuizViewModel(now: { time }, saveRecord: { _ in
            attempts += 1
            if attempts == 1 { throw Failure.disk }
        })
        vm.start()
        for _ in 0..<12 {
            vm.recordAnswer(try XCTUnwrap(vm.currentQuestion).correctIndex, questionToken: vm.questionToken)
            time += 0.81
            vm.tick()
        }
        XCTAssertNotNil(vm.saveError)
        XCTAssertEqual(vm.bestScore(for: .medium), 0)
        vm.retrySave()
        XCTAssertEqual(vm.bestScore(for: .medium), 12)
        XCTAssertNil(vm.saveError)
    }
}
