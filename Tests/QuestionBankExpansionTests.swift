import XCTest
@testable import IQTest

@MainActor
final class QuestionBankExpansionTests: XCTestCase {
    func testExpandedRavenPoolCanSupplyEveryDifficultyAndCategory() throws {
        let bank = try QuestionLoader.loadValidated()
        XCTAssertEqual(bank.count, 288)
        XCTAssertEqual(Set(bank.map(\.id)).count, 288)
        XCTAssertEqual(Set(bank.map(\.prompt)).count, bank.count, "同一题干不能通过重复收录增加题量")
        for difficulty in Difficulty.allCases {
            for category in TestType.raven.categories {
                XCTAssertEqual(bank.filter { $0.difficulty == difficulty && $0.category == category }.count, 24)
            }
        }
    }

    func testRavenRejectsBrokenAnswerKeysDuplicatesAndMissingStrata() throws {
        let original = try JSONEncoder().encode(QuestionLoader.load())
        XCTAssertNoThrow(try QuestionLoader.decode(original), "损坏前的对照数据必须能通过校验")
        let mutations: [(inout [[String: Any]]) -> Void] = [
            { $0[0]["correctIndex"] = 9 },
            { $0[1]["id"] = $0[0]["id"] },
            { $0[1]["prompt"] = $0[0]["prompt"] },
            { $0[0]["options"] = ["same", "same", "same", "same"] },
            { $0[0]["explanation"] = "  " },
            { $0.removeAll { $0["category"] as? String == "逻辑推理" } }
        ]
        for mutate in mutations {
            var rows = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [[String: Any]])
            mutate(&rows)
            XCTAssertThrowsError(try QuestionLoader.decode(JSONSerialization.data(withJSONObject: rows)))
        }
    }

    func testInvalidRavenBankDoesNotStartOrSaveAnEmptySession() {
        var saved = 0
        let vm = QuizViewModel(loader: { [] }, saveRecord: { _ in saved += 1 })
        vm.start()
        vm.tick()
        XCTAssertEqual(vm.phase, .ready)
        XCTAssertNotNil(vm.bankError)
        XCTAssertEqual(saved, 0)
    }

    func testRavenCanCompleteARoundEntirelyFromNewItems() throws {
        let key = "bestScore_瑞文_高级"
        let previous = UserDefaults.standard.object(forKey: key)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        let newItems = try QuestionLoader.loadValidated().filter { $0.id >= 145 }
        var time: TimeInterval = 1000
        var records: [TestRecord] = []
        let vm = QuizViewModel(loader: { newItems }, now: { time }, saveRecord: { records.append($0) })
        vm.difficulty = .hard
        vm.start()
        for _ in 0..<12 {
            let question = try XCTUnwrap(vm.currentQuestion)
            XCTAssertGreaterThanOrEqual(question.id, 145)
            vm.recordAnswer(question.correctIndex, questionToken: vm.questionToken)
            time += 0.81
            vm.tick()
        }
        XCTAssertEqual(vm.phase, .finished)
        XCTAssertEqual(vm.score, 12)
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(record.reviewItems?.count, 12)
        XCTAssertEqual(record.ravenEstimate?.bankVersion, "raven-practice-2026-10-21-v2")
        XCTAssertTrue(record.reviewItems?.allSatisfy { Int($0.id) ?? 0 >= 145 } ?? false)
    }

    func testQuestionSetsHaveDisjointStableIDsAndMatchingModels() throws {
        let a = try WechslerLoader.loadValidated(.a)
        let b = try WechslerLoader.loadValidated(.b)
        XCTAssertEqual(a.count, 120)
        XCTAssertEqual(b.count, 120)
        XCTAssertTrue(Set(a.map(\.id)).isDisjoint(with: b.map(\.id)))
        for set in WechslerQuestionSet.allCases {
            let bank = try WechslerLoader.loadValidated(set)
            try WechslerIQModel.load(set).validate(for: bank)
            for subtest in WechslerSubtest.allCases {
                XCTAssertEqual(bank.filter { $0.subtest == subtest }.map(\.order), Array(1...12))
            }
        }
        XCTAssertThrowsError(try WechslerIQModel.load(.a).validate(for: b))
        XCTAssertThrowsError(try WechslerIQModel.load(.b).validate(for: a))
    }

    func testQuestionSetBCompletes120ItemsAndArchivesItsOwnEstimateAndAnswers() throws {
        var time: TimeInterval = 1000
        var records: [TestRecord] = []
        let vm = WechslerViewModel(now: { time }, saveRecord: { records.append($0) })
        vm.start(questionSet: .b)
        for _ in 0..<120 {
            if vm.phase == .briefing {
                vm.answerTutorial(vm.instructions.sample.correctAnswer)
                vm.beginSubtest()
            }
            let item = try XCTUnwrap(vm.currentItem)
            XCTAssertTrue(item.id.hasPrefix("b-"))
            if vm.phase == .stimulus {
                time += Double(item.displaySeconds ?? 4)
                vm.tick()
            }
            if item.requiresRecall {
                vm.submitRecall(try XCTUnwrap(item.expectedRecall), for: item.id)
            } else {
                vm.choose(optionID: try XCTUnwrap(vm.presentedOptions.first { $0.score == item.maxScore }).id, for: item.id)
            }
        }
        XCTAssertEqual(vm.phase, .finished)
        XCTAssertEqual(vm.rawScore, 156)
        XCTAssertEqual(vm.maxRaw, 156)
        XCTAssertNotNil(vm.iqEstimate)
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(record.questionSet, .b)
        XCTAssertEqual(record.responses?.count, 120)
        XCTAssertEqual(record.reviewItems?.count, 120)
        XCTAssertEqual(record.iqEstimate?.modelVersion, "irt-heuristic-form-b-v1")
        let decoded = try JSONDecoder().decode(TestRecord.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(decoded.questionSet, .b)
        XCTAssertEqual(decoded.reviewItems?.first?.id, "b-block-01")
    }

    func testPracticeCanUseNewItemsFromTheCombinedPool() throws {
        let key = "wechslerPracticePercentagesV2"
        let previous = UserDefaults.standard.object(forKey: key)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        let a = try WechslerLoader.loadValidated(.a), b = try WechslerLoader.loadValidated(.b)
        var requested: [WechslerQuestionSet] = []
        let vm = WechslerViewModel(loader: { set in
            requested.append(set)
            // 将积木练习候选限定为真实 B 组，确定性验证新题可达。
            return set == .a ? a.filter { $0.subtest != .block } : b
        }, saveRecord: { _ in XCTFail("单项练习不应写完整历史") })
        vm.start(practice: .block)
        XCTAssertEqual(requested, [.a, .b])
        XCTAssertEqual(vm.itemCount, 3)
        vm.answerTutorial(vm.instructions.sample.correctAnswer)
        vm.beginSubtest()
        for section in 0..<3 {
            let item = try XCTUnwrap(vm.currentItem)
            XCTAssertTrue(item.id.hasPrefix("b-block-"))
            XCTAssertTrue((section * 4 + 1...section * 4 + 4).contains(item.order))
            vm.choose(optionID: try XCTUnwrap(vm.presentedOptions.first { $0.score == 0 }).id, for: item.id)
        }
        XCTAssertEqual(vm.phase, .finished)
    }
}
