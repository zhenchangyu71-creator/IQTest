import XCTest
@testable import IQTest

@MainActor
final class QuestionBankExpansionTests: XCTestCase {
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

    func testExpandedRavenPoolCanSupplyEveryDifficultyAndCategory() throws {
        let bank = try QuestionLoader.loadValidated()
        XCTAssertEqual(bank.count, 432)
        XCTAssertEqual(Set(bank.map(\.id)).count, 432)
        XCTAssertEqual(Set(bank.map(\.prompt)).count, bank.count, "同一题干不能通过重复收录增加题量")
        for difficulty in Difficulty.allCases {
            for category in TestType.raven.categories {
                XCTAssertEqual(bank.filter { $0.difficulty == difficulty && $0.category == category }.count, 36)
            }
        }
    }

    func testRavenPromptsAreUniqueIgnoringWhitespace() throws {
        // 只去首尾空白的话，「X Y X Y X ？」与「X Y X Y X ？」会被当成两道不同的题，
        // 而它们其实是同一道题的两份副本——同一轮会同时抽到两道一样的题。
        let bank = try QuestionLoader.loadValidated()
        let normalized = bank.map { $0.prompt.split(whereSeparator: { $0.isWhitespace }).joined() }
        XCTAssertEqual(Set(normalized).count, bank.count, "去掉空白后不应有重复题干")
    }

    func testRavenPatternAnswerKeysMatchTheirExplanations() throws {
        // 图形规律题的答案键必须与解析给出的答案一致。
        // 这条曾真的错过：「交替」规则把答案写成了序列的第一项，
        // 而解析说的是交替之后的另一项——正确答案被排除在选项之外，
        // 用户无论怎么选都答不对。而结构校验（重复题干、选项重复、
        // 答案索引越界）完全看不出这类错误。
        let bank = try QuestionLoader.loadValidated()
        // (正则, 答案所在的捕获组, 捕获组到选项的变换)
        let rules: [(NSRegularExpression, Int, (String) -> String)] = [
            (try NSRegularExpression(pattern: "(.)\\s*与\\s*(.)\\s*交替出现，\\1\\s*之后应为\\s*(.)"), 3, { $0 }),
            (try NSRegularExpression(pattern: "以\\s*(.)\\s*(.)\\s*(.)\\s*为一组循环，第三组第三位应为\\s*(.)"), 4, { $0 }),
            (try NSRegularExpression(pattern: "以\\s*(.)\\s*(.)\\s*(.)\\s*(.)\\s*为一组循环，第二组第二位应为\\s*(.)"), 5, { $0 }),
            (try NSRegularExpression(pattern: "以\\s*(.)\\s*(.)\\s*(.)\\s*为一组循环，第三组第二位应为\\s*(.)"), 4, { $0 }),
            (try NSRegularExpression(pattern: "(.)\\s*(.)\\s*(.)\\s*(.)\\s*之后回到\\s*(.)"), 5, { $0 }),
            (try NSRegularExpression(pattern: "符号数量依次递增，第四组应有 4 个\\s*(.)"), 1, { $0 + $0 + $0 + $0 }),
            // 兜底：早期题目的解析写成「实心圆与空心圆交替出现，● 之后应为 ○」，
            // 符号对是名称而不是符号，靠「之后应为」后面的那个符号取答案。
            (try NSRegularExpression(pattern: "之后应为\\s*([^\\s。]+)"), 1, { $0 })
        ]
        var checked = 0
        var alternatingTotal = 0
        var alternatingChecked = 0
        for question in bank where question.category == .pattern {
            let full = NSRange(question.explanation.startIndex..., in: question.explanation)
            // 答案键写反的正是「交替」类，这类必须逐题检查。
            // 早期题目的解析用名称（实心圆与空心圆）而非符号，规则匹配不到，
            // 因此这里只统计符号对符号的那一批，由兜底规则覆盖其余。
            let isSymbolAlternating = rules[0].0.firstMatch(in: question.explanation, range: full) != nil
            if isSymbolAlternating { alternatingTotal += 1 }
            guard let rule = rules.first(where: {
                $0.0.firstMatch(in: question.explanation, range: full) != nil
            }), let match = rule.0.firstMatch(in: question.explanation, range: full),
                  let range = Range(match.range(at: rule.1), in: question.explanation) else { continue }
            let expected = rule.2(String(question.explanation[range]))
            let actual = question.options[question.correctIndex]
            XCTAssertEqual(actual, expected,
                           "题 \(question.id)：解析说应为 \(expected)，答案键却指向 \(actual)")
            checked += 1
            if isSymbolAlternating { alternatingChecked += 1 }
        }
        XCTAssertGreaterThan(checked, 40, "应当检查到相当数量的图形规律题")
        XCTAssertEqual(alternatingChecked, alternatingTotal,
                       "「交替」类图形规律题必须逐题检查")
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
        XCTAssertEqual(record.ravenEstimate?.bankVersion, "raven-practice-2026-10-23-v4")
        XCTAssertTrue(record.reviewItems?.allSatisfy { Int($0.id) ?? 0 >= 145 } ?? false)
    }

    func testQuestionSetsHaveDisjointStableIDsAndMatchingModels() throws {
        let a = try WechslerLoader.loadValidated(.a)
        let b = try WechslerLoader.loadValidated(.b)
        XCTAssertEqual(a.count, 480)
        XCTAssertEqual(b.count, 480)
        XCTAssertTrue(Set(a.map(\.id)).isDisjoint(with: b.map(\.id)))
        for set in WechslerQuestionSet.allCases {
            let bank = try WechslerLoader.loadValidated(set)
            try WechslerIQModel.load(set).validate(for: bank)
            for subtest in WechslerSubtest.allCases {
                XCTAssertEqual(bank.filter { $0.subtest == subtest }.map(\.order), Array(1...48))
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
        XCTAssertEqual(record.iqEstimate?.modelVersion, "irt-heuristic-form-b-v2")
        let decoded = try JSONDecoder().decode(TestRecord.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(decoded.questionSet, .b)
        // 抽题是随机的（优先没做过的），这里只校验题号归属，不锁定具体题目。
        XCTAssertTrue(decoded.reviewItems?.first?.id.hasPrefix("b-block-") == true)
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
        // 练习池按题量三等分，段边界随题池扩大而变化。
        let segment = b.filter { $0.subtest == .block }.count / 3
        for section in 0..<3 {
            let item = try XCTUnwrap(vm.currentItem)
            XCTAssertTrue(item.id.hasPrefix("b-block-"))
            XCTAssertTrue((section * segment + 1...section * segment + segment).contains(item.order))
            vm.choose(optionID: try XCTUnwrap(vm.presentedOptions.first { $0.score == 0 }).id, for: item.id)
        }
        XCTAssertEqual(vm.phase, .finished)
    }
}
