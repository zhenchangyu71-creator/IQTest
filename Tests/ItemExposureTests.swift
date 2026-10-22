import XCTest
@testable import IQTest

/// 抽题轮换的测试：多次测试不应反复遇到同样的题。
///
/// 题库有限时重复出题会让复测分数混入练习效应——看过解析再遇到同一题，分数必然虚高。
/// 抽题时优先选没做过的题，题池全部做过时才重新开始一轮。
@MainActor
final class ItemExposureTests: XCTestCase {
    private let ravenKey = ItemExposureStore.bankKey("raven", TestType.raven.rawValue, Difficulty.medium.rawValue)
    private let wechslerKey = ItemExposureStore.bankKey("wechsler", WechslerQuestionSet.a.rawValue)

    override func setUp() {
        super.setUp()
        ItemExposureStore.reset(for: ravenKey)
        ItemExposureStore.reset(for: wechslerKey)
    }

    override func tearDown() {
        ItemExposureStore.reset(for: ravenKey)
        ItemExposureStore.reset(for: wechslerKey)
        super.tearDown()
    }

    func testExposureStoreRoundTripsAndResets() {
        XCTAssertTrue(ItemExposureStore.seen(for: ravenKey).isEmpty)
        ItemExposureStore.markSeen(["a", "b", "a"], for: ravenKey)
        XCTAssertEqual(ItemExposureStore.seen(for: ravenKey), ["a", "b"])
        XCTAssertTrue(ItemExposureStore.hasRecord(for: ravenKey))
        ItemExposureStore.reset(for: ravenKey)
        XCTAssertTrue(ItemExposureStore.seen(for: ravenKey).isEmpty)
        XCTAssertFalse(ItemExposureStore.hasRecord(for: ravenKey))
    }

    func testRavenSecondRoundAvoidsTheFirstRoundsQuestions() {
        let first = QuizViewModel()
        first.testType = .raven
        first.difficulty = .medium
        first.start()
        let firstIDs = first.questions.map { String($0.id) }
        XCTAssertEqual(firstIDs.count, 12)
        ItemExposureStore.markSeen(firstIDs, for: ravenKey)

        let second = QuizViewModel()
        second.testType = .raven
        second.difficulty = .medium
        second.start()
        let secondIDs = second.questions.map { String($0.id) }
        XCTAssertEqual(secondIDs.count, 12)
        XCTAssertTrue(Set(firstIDs).isDisjoint(with: Set(secondIDs)),
                      "第二轮抽到了第一轮做过的题")
    }

    func testWechslerSecondRoundAvoidsTheFirstRoundsQuestions() {
        let first = WechslerViewModel()
        first.start(questionSet: .a)
        let firstIDs = first.items.map(\.id)
        XCTAssertEqual(firstIDs.count, 120)
        ItemExposureStore.markSeen(firstIDs, for: wechslerKey)

        let second = WechslerViewModel()
        second.start(questionSet: .a)
        let secondIDs = second.items.map(\.id)
        XCTAssertEqual(secondIDs.count, 120)
        XCTAssertTrue(Set(firstIDs).isDisjoint(with: Set(secondIDs)),
                      "第二轮抽到了第一轮做过的题")
        // 每个分测验仍抽满 12 题，题池从 12 扩到 24 才有轮换的余地。
        for subtest in WechslerSubtest.allCases {
            XCTAssertEqual(second.items.filter { $0.subtest == subtest }.count, 12, subtest.rawValue)
        }
    }

    func testWechslerPoolExhaustionStartsOverInsteadOfRepeatingForever() {
        // 题池抽干后应重新开始一轮，而不是永远重复同一批题。
        let pool = try! WechslerLoader.loadValidated(.a)
        let all = pool.map(\.id)
        ItemExposureStore.markSeen(all, for: wechslerKey)
        XCTAssertTrue(ItemExposureStore.seen(for: wechslerKey).count == all.count)

        let vm = WechslerViewModel()
        vm.start(questionSet: .a)
        XCTAssertEqual(vm.items.count, 120)
        XCTAssertFalse(vm.items.isEmpty)
    }

    func testWechslerPoolIsLargeEnoughForRotation() throws {
        // 每个分测验的题池必须大于单轮题量，否则轮换无从谈起。
        let bank = try WechslerLoader.loadValidated(.a)
        for subtest in WechslerSubtest.allCases {
            let count = bank.filter { $0.subtest == subtest }.count
            XCTAssertGreaterThan(count, WechslerViewModel.itemsPerSubtest,
                                 "\(subtest.rawValue) 题池不足以轮换")
        }
    }

    func testOnlyAnsweredItemsAreMarkedAsSeen() throws {
        // 提前结束时未作答的题不该被记为「做过」——用户没见过它们，下一轮仍应抽得到。
        var time: TimeInterval = 1000
        let vm = WechslerViewModel(now: { time }, saveRecord: { _ in })
        vm.start(questionSet: .a)
        var answered = 0
        while answered < 5, vm.phase != .finished {
            if vm.phase == .briefing {
                vm.answerTutorial(vm.instructions.sample.correctAnswer)
                vm.beginSubtest()
            }
            guard let item = vm.currentItem else { break }
            if vm.phase == .stimulus {
                time += Double(item.displaySeconds ?? 4)
                vm.tick()
            }
            if item.requiresRecall {
                vm.submitRecall(try XCTUnwrap(item.expectedRecall), for: item.id)
            } else if let option = vm.presentedOptions.first(where: { $0.score == item.maxScore }) {
                vm.choose(optionID: option.id, for: item.id)
            }
            answered += 1
        }
        vm.endAndSave()

        let seen = ItemExposureStore.seen(for: wechslerKey)
        XCTAssertEqual(seen.count, answered, "只应记录实际作答过的题")
        for response in vm.responses {
            XCTAssertTrue(seen.contains(response.itemID))
        }
    }
}
