import XCTest
@testable import IQTest

final class WechslerIQEstimatorTests: XCTestCase {
    private func binaryRecall(_ id: String) -> WechslerItem {
        WechslerItem(id: id, subtest: .digitspan, prompt: "顺序回忆", options: ["1 2 3", "3 2 1"],
                     optionScores: [1, 0], explanation: "123", presentation: "digits", stimulus: "1 2 3",
                     displaySeconds: 4, recallRule: .forward)
    }
    private func fullResponses(_ items: [WechslerItem]) -> [WechslerResponse] {
        items.map { item in
            WechslerResponse(itemID: item.id, subtest: item.subtest, answer: item.correctAnswer,
                             score: item.maxScore, maxScore: item.maxScore, outcome: .answered, elapsedSeconds: 1)
        }
    }

    func testChoiceGuessFloorAndRecallNoRecognitionGuessFloor() throws {
        let choice = try XCTUnwrap(WechslerLoader.loadValidated().first { $0.id == "block-01" })
        let parameter = WechslerIQModel.ItemParameter(itemID: choice.id, discrimination: 1, thresholds: [0])
        let p = WechslerIQEstimator.probabilities(item: choice, parameter: parameter, theta: 0)
        XCTAssertEqual(try XCTUnwrap(p[1]), 0.625, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(p[0]), 0.375, accuracy: 1e-12)
        let recall = binaryRecall("recall")
        let r = WechslerIQEstimator.probabilities(item: recall, parameter: parameter, theta: 0)
        XCTAssertEqual(try XCTUnwrap(r[1]), 0.5, accuracy: 1e-12)
    }

    func testGradedProbabilitiesRetainPartialCredit() throws {
        let question = try XCTUnwrap(WechslerLoader.loadValidated().first { $0.id == "vocabulary-01" })
        let parameter = WechslerIQModel.ItemParameter(itemID: question.id, discrimination: 1,
                                                     thresholds: [-log(3), log(3)])
        let p = WechslerIQEstimator.probabilities(item: question, parameter: parameter, theta: 0)
        XCTAssertEqual(try XCTUnwrap(p[0]), 0.125, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(p[1]), 0.4375, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(p[2]), 0.4375, accuracy: 1e-12)
    }

    func testAllItemProbabilityDistributionsAreValidAcrossGrid() throws {
        let bank = try WechslerLoader.loadValidated(), model = try WechslerIQModel.load()
        try model.validate(for: bank)
        let parameters = Dictionary(uniqueKeysWithValues: model.items.map { ($0.itemID, $0) })
        for question in bank {
            let parameter = try XCTUnwrap(parameters[question.id])
            for theta in stride(from: -5.0, through: 5.0, by: 0.25) {
                let p = WechslerIQEstimator.probabilities(item: question, parameter: parameter, theta: theta)
                XCTAssertEqual(p.values.reduce(0, +), 1, accuracy: 1e-12, question.id)
                XCTAssertTrue(p.values.allSatisfy { $0.isFinite && (0...1).contains($0) }, question.id)
            }
        }
    }

    func testPosteriorHasKnownSymmetryAndDirection() throws {
        let a = binaryRecall("a"), b = binaryRecall("b")
        let parameter = WechslerIQModel.ItemParameter(itemID: "unused-by-math", discrimination: 1, thresholds: [0])
        // L(theta) = sigmoid(theta) * (1-sigmoid(theta)); 对称 N(0,1) 先验下均值必须为零。
        let balanced = try WechslerIQEstimator.posteriorMean(evidence: [(a, parameter, 1), (b, parameter, 0)])
        let correct = try WechslerIQEstimator.posteriorMean(evidence: [(a, parameter, 1)])
        let wrong = try WechslerIQEstimator.posteriorMean(evidence: [(a, parameter, 0)])
        XCTAssertEqual(balanced, 0, accuracy: 1e-12)
        XCTAssertGreaterThan(correct, 0)
        XCTAssertEqual(correct, -wrong, accuracy: 1e-12)
    }

    func testPartialScoreProducesIntermediatePosterior() throws {
        let question = try XCTUnwrap(WechslerLoader.loadValidated().first { $0.id == "vocabulary-01" })
        let parameter = WechslerIQModel.ItemParameter(itemID: question.id, discrimination: 1, thresholds: [-1, 1])
        let means = try (0...2).map { try WechslerIQEstimator.posteriorMean(evidence: [(question, parameter, $0)]) }
        XCTAssertLessThan(means[0], means[1])
        XCTAssertLessThan(means[1], means[2])
    }

    func testPerfectRunHasValueButRemainsHeuristicAndFlagsCeiling() throws {
        let bank = try WechslerLoader.loadValidated(), model = try WechslerIQModel.load()
        let responses = fullResponses(bank)
        let result = try WechslerIQEstimator.estimate(items: bank, responses: responses, model: model)
        XCTAssertGreaterThan(result.value, 100)
        XCTAssertEqual(result.value, Int((100 + 15 * result.theta).rounded()))
        XCTAssertEqual(result.calibrationStatus, .heuristic)
        XCTAssertFalse(result.ageAdjusted)
        XCTAssertEqual(result.answeredCount, 480)
        XCTAssertEqual(result.timedOutCount, 0)
        XCTAssertEqual(result.flags, [.ceiling])
        let reordered = try WechslerIQEstimator.estimate(items: bank, responses: responses.reversed(), model: model)
        XCTAssertEqual(result.theta, reordered.theta, accuracy: 1e-12)
    }

    func testAllWrongFlagsFloorAndDoesNotReturnNeutral100() throws {
        let bank = try WechslerLoader.loadValidated()
        let responses = bank.map { item in
            WechslerResponse(itemID: item.id, subtest: item.subtest,
                             answer: item.requiresRecall ? "0" : item.options[item.optionScores.firstIndex(of: 0)!],
                             score: 0, maxScore: item.maxScore, outcome: .answered, elapsedSeconds: 1)
        }
        let result = try WechslerIQEstimator.estimate(items: bank, responses: responses, model: WechslerIQModel.load())
        XCTAssertLessThan(result.value, 100)
        XCTAssertEqual(result.flags, [.floor])
    }

    func testLowNonzeroScoreDoesNotClipPosteriorAtMinusFive() throws {
        let bank = try WechslerLoader.loadValidated()
        let responses = bank.enumerated().map { index, item in
            WechslerResponse(itemID: item.id, subtest: item.subtest,
                             answer: index == 0 ? item.correctAnswer : (item.requiresRecall ? "0" : item.options[item.optionScores.firstIndex(of: 0)!]),
                             score: index == 0 ? item.maxScore : 0, maxScore: item.maxScore,
                             outcome: .answered, elapsedSeconds: 1)
        }
        let result = try WechslerIQEstimator.estimate(items: bank, responses: responses, model: WechslerIQModel.load())
        // 题库扩充到每分测验 48 题后独立细网格积分约为 -6.21；要点是不得截在 -5 内。
        XCTAssertLessThan(result.theta, -5.0, "能力估计被截断在 -5")
        XCTAssertEqual(result.theta, -6.207249, accuracy: 0.01)
        XCTAssertEqual(result.value, 7)
    }

    func testMissingDuplicateAndForgedResponsesAreRejected() throws {
        let bank = try WechslerLoader.loadValidated(), model = try WechslerIQModel.load()
        let original = fullResponses(bank)
        XCTAssertThrowsError(try WechslerIQEstimator.estimate(items: bank, responses: Array(original.dropLast()), model: model))
        var duplicate = original
        duplicate[1] = duplicate[0]
        XCTAssertThrowsError(try WechslerIQEstimator.estimate(items: bank, responses: duplicate, model: model))
        var forged = original
        let first = bank[0]
        forged[0] = WechslerResponse(itemID: first.id, subtest: first.subtest, answer: "不存在的选项",
                                     score: first.maxScore, maxScore: first.maxScore, outcome: .answered, elapsedSeconds: 1)
        XCTAssertThrowsError(try WechslerIQEstimator.estimate(items: bank, responses: forged, model: model))
    }

    func testPracticeCannotGenerateIQFromOnlyThreeItems() throws {
        let bank = try WechslerLoader.loadValidated()
        let three = Array(bank.prefix(3))
        XCTAssertThrowsError(try WechslerIQEstimator.estimate(items: bank, responses: fullResponses(three), model: WechslerIQModel.load()))
    }

    func testTimeoutThresholdIsInclusiveAndTooManyTimeoutsDoNotProduceIQ() throws {
        let bank = try WechslerLoader.loadValidated(), model = try WechslerIQModel.load()
        var responses = fullResponses(bank)
        func timeout(_ index: Int) -> WechslerResponse {
            let item = bank[index]
            return WechslerResponse(itemID: item.id, subtest: item.subtest, answer: nil, score: 0,
                                     maxScore: item.maxScore, outcome: .timedOut, elapsedSeconds: Double(item.subtest.timeLimit))
        }
        // 超时门槛是全部项目的 20%：题库 480 题时为 96 题。
        for index in 0..<96 { responses[index] = timeout(index) }
        let result = try WechslerIQEstimator.estimate(items: bank, responses: responses, model: model)
        XCTAssertEqual(result.timedOutCount, 96)
        XCTAssertTrue(result.flags.contains(.timeouts))
        responses[96] = timeout(96)
        XCTAssertThrowsError(try WechslerIQEstimator.estimate(items: bank, responses: responses, model: model))
    }

    func testModelRejectsWrongVersionsMissingIDsAndInvalidThresholds() throws {
        let bank = try WechslerLoader.loadValidated(), model = try WechslerIQModel.load()
        let wrongVersion = WechslerIQModel(version: model.version, bankVersion: "another-bank", calibrationStatus: .heuristic, items: model.items)
        XCTAssertThrowsError(try wrongVersion.validate(for: bank))
        let missing = WechslerIQModel(version: model.version, bankVersion: model.bankVersion, calibrationStatus: .heuristic, items: Array(model.items.dropLast()))
        XCTAssertThrowsError(try missing.validate(for: bank))
        var invalid = model.items
        invalid[0] = .init(itemID: invalid[0].itemID, discrimination: .nan, thresholds: [0])
        XCTAssertThrowsError(try WechslerIQModel(version: model.version, bankVersion: model.bankVersion, calibrationStatus: .heuristic, items: invalid).validate(for: bank))
        let index = try XCTUnwrap(model.items.firstIndex { $0.itemID == "vocabulary-01" })
        invalid = model.items
        invalid[index] = .init(itemID: invalid[index].itemID, discrimination: 1, thresholds: [1, -1])
        XCTAssertThrowsError(try WechslerIQModel(version: model.version, bankVersion: model.bankVersion, calibrationStatus: .heuristic, items: invalid).validate(for: bank))
    }

    func testEstimateRecordKeepsModelVersionWithoutPollutingNormedIQ() throws {
        let bank = try WechslerLoader.loadValidated()
        let estimate = try WechslerIQEstimator.estimate(items: bank, responses: fullResponses(bank), model: WechslerIQModel.load())
        let record = TestRecord(date: Date(), testType: .wechsler, difficulty: .medium, score: 156, total: 156,
                                iq: nil, percentile: nil, scoringVersion: WechslerLoader.bankVersion, iqEstimate: estimate)
        let decoded = try JSONDecoder().decode(TestRecord.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(decoded.iqEstimate?.value, estimate.value)
        XCTAssertEqual(decoded.iqEstimate?.modelVersion, "irt-heuristic-v2")
        XCTAssertEqual(decoded.iqEstimate?.calibrationStatus, .heuristic)
        XCTAssertNil(decoded.iq)
        XCTAssertNil(decoded.displayedIQ)
        XCTAssertNil(decoded.percentile)
    }
}
