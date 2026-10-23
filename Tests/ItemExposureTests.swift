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

    func testWechslerRoundKeepsTwelveItemsPerSubtestWhenUnseenItemsRunShort() throws {
        // 未做过的题不够时必须用做过的题补足：题量一变，分母就变了，
        // 不同轮次的得分率无法比较。
        let bank = try WechslerLoader.loadValidated(.a)
        let blockIDs = bank.filter { $0.subtest == .block }.map(\.id)
        ItemExposureStore.markSeen(Array(blockIDs.dropLast(4)), for: wechslerKey)

        let vm = WechslerViewModel()
        vm.start(questionSet: .a)
        XCTAssertEqual(vm.items.count, 120)
        for subtest in WechslerSubtest.allCases {
            XCTAssertEqual(vm.items.filter { $0.subtest == subtest }.count, 12, subtest.rawValue)
        }
    }

    func testRavenRoundKeepsTwelveItemsWhenUnseenItemsRunShort() throws {
        // 同一约束在瑞文侧同样成立：某一类只剩两道没做过的题时，
        // 这一轮仍然是 12 题，而不是 11 题。
        let bank = try QuestionLoader.loadValidated()
        let category = TestType.raven.categories[0]
        let ids = bank.filter { $0.difficulty == .medium && $0.category == category }.map { String($0.id) }
        ItemExposureStore.markSeen(Array(ids.dropLast(2)), for: ravenKey)

        let vm = QuizViewModel()
        vm.testType = .raven
        vm.difficulty = .medium
        vm.start()
        XCTAssertEqual(vm.questions.count, 12)
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
    func testWechslerRoundHasNoTwoQuestionsWithTheSameContent() throws {
        // 题库里存在内容完全相同的题——扩充时把原有题又追加了一遍，
        // 词汇、常识、符号编码三个分测验各有 12 对。同一轮里抽到两道一样的题，
        // 练习体验与测量都会失真。
        let vm = WechslerViewModel()
        vm.start(questionSet: .a)
        XCTAssertEqual(vm.items.count, 120, "题量必须恒定")
        var keys = Set<String>()
        for item in vm.items {
            XCTAssertTrue(keys.insert(item.contentKey).inserted,
                          "同一轮出现了内容相同的两道题：\(item.id)")
        }
    }

    func testWechslerDoesNotRedrawASeenQuestionUnderAnotherID() throws {
        // 做过一道题后，内容相同的另一份不应再被当成「新题」抽到：
        // 否则复测会遇到原题，练习效应直接混进分数。
        let bank = try WechslerLoader.loadValidated(.a)
        let pair = try XCTUnwrap(duplicatePair(in: bank), "题库里应当存在内容相同的两道题")
        ItemExposureStore.markSeen([pair.0], for: wechslerKey)
        let vm = WechslerViewModel()
        vm.start(questionSet: .a)
        XCTAssertFalse(vm.items.contains { $0.id == pair.1 },
                       "同内容的另一份不应被抽到：\(pair.0) 与 \(pair.1)")
    }

    private func duplicatePair(in bank: [WechslerItem]) -> (String, String)? {
        var first: [String: String] = [:]
        for item in bank {
            if let previous = first[item.contentKey] { return (previous, item.id) }
            first[item.contentKey] = item.id
        }
        return nil
    }
    func testSingleSubtestPracticeHasNoTwoQuestionsWithTheSameContent() throws {
        // 单项练习从三段里各取一题。题库里存在内容完全相同的题，
        // 重复对分布在不同段里（词汇 13/25、常识 14/26…），两段可能取到同一道题。
        // 单项练习不记曝光，只能靠当次去重来避免。
        for subtest in WechslerSubtest.allCases {
            for _ in 0..<5 {
                let vm = WechslerViewModel()
                vm.start(practice: subtest)
                XCTAssertEqual(vm.items.count, 3, subtest.rawValue)
                var keys = Set<String>()
                for item in vm.items {
                    XCTAssertTrue(keys.insert(item.contentKey).inserted,
                                  "\(subtest.rawValue) 单项练习出现了内容相同的两道题：\(item.id)")
                }
            }
        }
    }
}
