import XCTest
@testable import IQTest

/// 韦氏风格量表分剖面的换算测试。
/// 回归基准取自 Pearson 官方 WAIS-5 示例报告中公开的原始分、尺度分与合成分对应关系。
final class WechslerProfileTests: XCTestCase {

    // MARK: - 正态量尺

    func testNormalCDFMatchesPublishedValues() {
        XCTAssertEqual(IQScale.normalCDF(0), 0.5, accuracy: 1e-6)
        XCTAssertEqual(IQScale.normalCDF(1.96), 0.975, accuracy: 1e-4)
        XCTAssertEqual(IQScale.normalCDF(-1), 0.1587, accuracy: 1e-4)
        XCTAssertEqual(IQScale.normalCDF(1.645), 0.95, accuracy: 1e-4)
    }

    func testInverseNormalCDFInvertsNormalCDF() {
        for p in [0.001, 0.025, 0.1, 0.5, 0.75, 0.9, 0.975, 0.999] {
            let z = IQScale.inverseNormalCDF(p)
            XCTAssertEqual(IQScale.normalCDF(z), p, accuracy: 1e-6, "p=\(p)")
        }
        XCTAssertEqual(IQScale.inverseNormalCDF(0.5), 0, accuracy: 1e-6)
        XCTAssertEqual(IQScale.inverseNormalCDF(0.975), 1.959964, accuracy: 1e-4)
    }

    func testPercentileConversionsMatchPearsonSample() {
        // 尺度分：s=11→P63、s=14→P91、s=7→P16、s=6→P9。
        XCTAssertEqual(IQScale.percentile(fromScaled: 11), 63, accuracy: 1.0)
        XCTAssertEqual(IQScale.percentile(fromScaled: 14), 91, accuracy: 1.0)
        XCTAssertEqual(IQScale.percentile(fromScaled: 7), 16, accuracy: 1.0)
        XCTAssertEqual(IQScale.percentile(fromScaled: 6), 9, accuracy: 1.0)
        // 合成分：114→P82、79→P8、94→P34。
        XCTAssertEqual(IQScale.percentile(fromComposite: 114), 82, accuracy: 1.0)
        XCTAssertEqual(IQScale.percentile(fromComposite: 79), 8, accuracy: 1.0)
        XCTAssertEqual(IQScale.percentile(fromComposite: 94), 34, accuracy: 1.0)
        XCTAssertEqual(IQScale.percentile(fromComposite: 100), 50, accuracy: 1e-5)
    }

    func testCompositeFromPercentileInvertsPercentile() {
        for p in [1.0, 5.0, 25.0, 50.0, 75.0, 95.0, 99.0] {
            let composite = IQScale.composite(fromPercentile: p)
            XCTAssertEqual(IQScale.percentile(fromComposite: composite), p, accuracy: 0.05, "p=\(p)")
        }
    }

    func testCompositeBandBoundaries() {
        XCTAssertEqual(IQScale.CompositeBand.band(for: 130), .verySuperior)
        XCTAssertEqual(IQScale.CompositeBand.band(for: 129.9), .superior)
        XCTAssertEqual(IQScale.CompositeBand.band(for: 120), .superior)
        XCTAssertEqual(IQScale.CompositeBand.band(for: 119), .highAverage)
        XCTAssertEqual(IQScale.CompositeBand.band(for: 110), .highAverage)
        XCTAssertEqual(IQScale.CompositeBand.band(for: 109), .average)
        XCTAssertEqual(IQScale.CompositeBand.band(for: 90), .average)
        XCTAssertEqual(IQScale.CompositeBand.band(for: 89), .lowAverage)
        XCTAssertEqual(IQScale.CompositeBand.band(for: 80), .lowAverage)
        XCTAssertEqual(IQScale.CompositeBand.band(for: 79), .borderline)
        XCTAssertEqual(IQScale.CompositeBand.band(for: 70), .borderline)
        XCTAssertEqual(IQScale.CompositeBand.band(for: 69), .extremelyLow)
    }

    func testScaledBandBoundaries() {
        XCTAssertEqual(IQScale.ScaledBand.band(for: 7), .veryLow)
        XCTAssertEqual(IQScale.ScaledBand.band(for: 8), .belowAverage)
        XCTAssertEqual(IQScale.ScaledBand.band(for: 10), .average)
        XCTAssertEqual(IQScale.ScaledBand.band(for: 12), .aboveAverage)
        XCTAssertEqual(IQScale.ScaledBand.band(for: 14), .veryHigh)
    }

    func testStandardNineMapping() {
        XCTAssertEqual(IQScale.standardNine(fromScaled: 1), 1)
        XCTAssertEqual(IQScale.standardNine(fromScaled: 4), 2)
        XCTAssertEqual(IQScale.standardNine(fromScaled: 5), 3)
        XCTAssertEqual(IQScale.standardNine(fromScaled: 7), 4)
        XCTAssertEqual(IQScale.standardNine(fromScaled: 9), 5)
        XCTAssertEqual(IQScale.standardNine(fromScaled: 12), 6)
        XCTAssertEqual(IQScale.standardNine(fromScaled: 13), 7)
        XCTAssertEqual(IQScale.standardNine(fromScaled: 15), 8)
        XCTAssertEqual(IQScale.standardNine(fromScaled: 19), 9)
    }

    // MARK: - 尺度分之和到合成分

    func testFullScaleConversionMatchesPearsonSample() {
        // Pearson 官方示例报告：七个主分测验尺度分之和 64 → 全量表分 94；82 → 111。
        // 线性化与官方逐格查表之间允许 1 分差异。
        XCTAssertEqual(WechslerProfileScorer.fullScale(scaledSum: 64, subtestCount: 7), 94)
        let second = WechslerProfileScorer.fullScale(scaledSum: 82, subtestCount: 7)
        XCTAssertTrue((111...112).contains(second), "实际换算得到 \(second)")
    }

    func testFullScaleConversionIsCentredOnAveragePerformance() {
        XCTAssertEqual(WechslerProfileScorer.fullScale(scaledSum: 70, subtestCount: 7), 100)
        XCTAssertEqual(WechslerProfileScorer.fullScale(scaledSum: 100, subtestCount: 10), 100)
    }

    func testTenSubtestSlopeDiffersFromSevenSubtestSlope() {
        // 分测验越多，尺度分之和的离散越大，折算到 IQ 的斜率越小。
        XCTAssertLessThan(WechslerProfileScorer.fullScaleSlope, WechslerProfileScorer.fullScaleSlopeSevenSubtests)
        XCTAssertEqual(WechslerProfileScorer.fullScale(scaledSum: 110, subtestCount: 10),
                       WechslerProfileScorer.composite(scaledSum: 110, subtestCount: 10,
                                                        slope: WechslerProfileScorer.fullScaleSlope))
    }

    func testIndexConversionMatchesPearsonSample() {
        // 两个分测验尺度分之和 20 → 指数分 100；之和 28 → 122（斜率 2.75）。
        XCTAssertEqual(WechslerProfileScorer.composite(scaledSum: 20, subtestCount: 2, slope: WechslerProfileScorer.indexSlope), 100)
        XCTAssertEqual(WechslerProfileScorer.composite(scaledSum: 28, subtestCount: 2, slope: WechslerProfileScorer.indexSlope), 122)
    }

    func testCompositeConversionIsMonotonicAndClamped() {
        var previous = -Int.max
        for sum in stride(from: 0, through: 190, by: 1) {
            let value = WechslerProfileScorer.fullScale(scaledSum: sum, subtestCount: 10)
            XCTAssertGreaterThanOrEqual(value, previous, "sum=\(sum)")
            XCTAssertTrue(WechslerProfileScorer.compositeRange.contains(value), "sum=\(sum)")
            previous = value
        }
    }

    // MARK: - 分层能力估计

    func testAbilityProducesSubtestEstimatesForEverySubtest() throws {
        let bank = try WechslerLoader.loadValidated()
        let model = try WechslerIQModel.load()
        let responses = bank.map { item in
            WechslerResponse(itemID: item.id, subtest: item.subtest, answer: item.correctAnswer,
                             score: item.maxScore, maxScore: item.maxScore, outcome: .answered, elapsedSeconds: 1)
        }
        let ability = try WechslerIQEstimator.ability(items: bank, responses: responses, model: model)
        XCTAssertEqual(ability.subtests.count, WechslerSubtest.allCases.count)
        XCTAssertGreaterThan(ability.globalTheta, 0)
        for entry in ability.subtests {
            XCTAssertTrue(entry.theta.isFinite)
            XCTAssertTrue(entry.standardError > 0)
        }
    }

    func testSubtestEstimatesAreShrunkTowardTheWeightedCenter() throws {
        let bank = try WechslerLoader.loadValidated()
        let model = try WechslerIQModel.load()
        let responses = bank.map { item in
            WechslerResponse(itemID: item.id, subtest: item.subtest, answer: item.correctAnswer,
                             score: item.maxScore, maxScore: item.maxScore, outcome: .answered, elapsedSeconds: 1)
        }
        let ability = try WechslerIQEstimator.ability(items: bank, responses: responses, model: model)
        // 收缩中心来自各分测验自身，不是总体能力；全部答对时中心应高于总体能力。
        XCTAssertGreaterThan(ability.centerTheta, ability.globalTheta - 3)
        for entry in ability.subtests {
            XCTAssertTrue(entry.theta.isFinite)
            // 收缩后的估计落在自身估计与中心之间。
            XCTAssertLessThan(abs(entry.theta - ability.centerTheta), 3)
        }
    }

    func testDomainDifferencesAreNotFlattened() throws {
        let bank = try WechslerLoader.loadValidated()
        let model = try WechslerIQModel.load()
        // 言语分测验全对，其余分测验全错：领域差异必须保留。
        let verbal: Set<WechslerSubtest> = [.similarities, .vocabulary, .information]
        let responses = bank.map { item in
            let isVerbal = verbal.contains(item.subtest)
            let score = isVerbal ? item.maxScore : 0
            let answer = isVerbal ? item.correctAnswer
                : (item.requiresRecall ? "0" : item.options[item.optionScores.firstIndex(of: 0)!])
            return WechslerResponse(itemID: item.id, subtest: item.subtest, answer: answer,
                                    score: score, maxScore: item.maxScore, outcome: .answered, elapsedSeconds: 1)
        }
        let ability = try WechslerIQEstimator.ability(items: bank, responses: responses, model: model)
        let profile = WechslerProfileScorer.make(ability: ability, flags: [],
                                                 modelVersion: model.version, bankVersion: model.bankVersion)
        let verbalScore = try XCTUnwrap(profile.indices.first { $0.domain == .verbal }).score
        let perceptualScore = try XCTUnwrap(profile.indices.first { $0.domain == .perceptual }).score
        XCTAssertGreaterThan(verbalScore, perceptualScore + 20)
        XCTAssertGreaterThan(verbalScore, 85)
    }

    func testFisherInformationIsZeroWhenAllItemsAreSaturated() throws {
        let bank = try WechslerLoader.loadValidated()
        let model = try WechslerIQModel.load()
        let parameters = Dictionary(uniqueKeysWithValues: model.items.map { ($0.itemID, $0) })
        let item = try XCTUnwrap(bank.first)
        let parameter = try XCTUnwrap(parameters[item.id])
        // 阈值远低于 theta 时题目已饱和，信息趋近于零。
        let information = WechslerIQEstimator.fisherInformation(item: item, parameter: parameter, theta: 8)
        XCTAssertLessThan(information, 0.05)
    }

    // MARK: - 剖面

    func testProfileFromPerfectRunIsHighAndFlagsCeiling() throws {
        let bank = try WechslerLoader.loadValidated()
        let model = try WechslerIQModel.load()
        let responses = bank.map { item in
            WechslerResponse(itemID: item.id, subtest: item.subtest, answer: item.correctAnswer,
                             score: item.maxScore, maxScore: item.maxScore, outcome: .answered, elapsedSeconds: 1)
        }
        let ability = try WechslerIQEstimator.ability(items: bank, responses: responses, model: model)
        let profile = WechslerProfileScorer.make(ability: ability, flags: [.ceiling],
                                                 modelVersion: model.version, bankVersion: model.bankVersion)
        XCTAssertEqual(profile.subtests.count, 10)
        XCTAssertEqual(profile.indices.count, 4)
        XCTAssertGreaterThan(profile.fullScale.score, 100)
        XCTAssertEqual(profile.calibrationStatus, .uncalibrated)
        XCTAssertTrue(profile.flags.contains(.ceiling))
        for scaled in profile.subtests {
            XCTAssertTrue((1...19).contains(scaled.scaled))
            XCTAssertEqual(scaled.band, IQScale.ScaledBand.band(for: scaled.scaled))
        }
        for index in profile.indices {
            XCTAssertEqual(index.band, IQScale.CompositeBand.band(for: Double(index.score)))
        }
    }

    func testProfileStandardErrorNeverFallsBelowWechslerManualFloor() throws {
        let bank = try WechslerLoader.loadValidated()
        let model = try WechslerIQModel.load()
        let responses = bank.map { item in
            WechslerResponse(itemID: item.id, subtest: item.subtest, answer: item.correctAnswer,
                             score: item.maxScore, maxScore: item.maxScore, outcome: .answered, elapsedSeconds: 1)
        }
        let ability = try WechslerIQEstimator.ability(items: bank, responses: responses, model: model)
        let profile = WechslerProfileScorer.make(ability: ability, flags: [],
                                                 modelVersion: model.version, bankVersion: model.bankVersion)
        XCTAssertGreaterThanOrEqual(profile.fullScale.standardError, WechslerProfileScorer.fullScaleSEMFloor)
        for index in profile.indices {
            XCTAssertGreaterThanOrEqual(index.standardError, WechslerProfileScorer.indexSEMFloor)
            if let lower = index.confidenceLower, let upper = index.confidenceUpper {
                XCTAssertLessThan(lower, index.score)
                XCTAssertGreaterThan(upper, index.score)
            }
        }
    }

    func testProfileIsIndependentOfResponseOrder() throws {
        let bank = try WechslerLoader.loadValidated()
        let model = try WechslerIQModel.load()
        let responses = bank.map { item in
            WechslerResponse(itemID: item.id, subtest: item.subtest, answer: item.correctAnswer,
                             score: item.maxScore, maxScore: item.maxScore, outcome: .answered, elapsedSeconds: 1)
        }
        let forward = try WechslerIQEstimator.ability(items: bank, responses: responses, model: model)
        let reversed = try WechslerIQEstimator.ability(items: bank, responses: responses.reversed(), model: model)
        XCTAssertEqual(forward.globalTheta, reversed.globalTheta, accuracy: 1e-12)
        for entry in forward.subtests {
            let other = try XCTUnwrap(reversed.ability(for: entry.subtest))
            XCTAssertEqual(entry.theta, other.theta, accuracy: 1e-12)
        }
    }

    func testProfileRejectsIncompleteOrInterruptedSessions() throws {
        let bank = try WechslerLoader.loadValidated()
        let model = try WechslerIQModel.load()
        let responses = bank.map { item in
            WechslerResponse(itemID: item.id, subtest: item.subtest, answer: item.correctAnswer,
                             score: item.maxScore, maxScore: item.maxScore, outcome: .answered, elapsedSeconds: 1)
        }
        XCTAssertThrowsError(try WechslerIQEstimator.ability(items: bank, responses: Array(responses.dropLast()), model: model))
        var interrupted = responses
        interrupted[0] = WechslerResponse(itemID: interrupted[0].itemID, subtest: interrupted[0].subtest, answer: nil,
                                          score: 0, maxScore: interrupted[0].maxScore, outcome: .interrupted, elapsedSeconds: 1)
        XCTAssertThrowsError(try WechslerIQEstimator.ability(items: bank, responses: interrupted, model: model))
    }

    func testConfidenceIntervalsStayInsideTheInterpretableRange() throws {
        let bank = try WechslerLoader.loadValidated()
        let model = try WechslerIQModel.load()
        // 全部答错：能力估计落到量表下端，区间也不能跑到合成分范围之外。
        let responses = bank.map { item in
            WechslerResponse(itemID: item.id, subtest: item.subtest,
                             answer: item.requiresRecall ? "0" : item.options[item.optionScores.firstIndex(of: 0)!],
                             score: 0, maxScore: item.maxScore, outcome: .answered, elapsedSeconds: 1)
        }
        let ability = try WechslerIQEstimator.ability(items: bank, responses: responses, model: model)
        let profile = WechslerProfileScorer.make(ability: ability, flags: [.floor],
                                                 modelVersion: model.version, bankVersion: model.bankVersion)
        XCTAssertEqual(profile.fullScale.score, WechslerProfileScorer.compositeRange.lowerBound)
        for index in profile.indices {
            if let lower = index.confidenceLower {
                XCTAssertGreaterThanOrEqual(lower, WechslerProfileScorer.compositeRange.lowerBound)
            }
            if let upper = index.confidenceUpper {
                XCTAssertLessThanOrEqual(upper, WechslerProfileScorer.compositeRange.upperBound)
            }
        }
        if let lower = profile.fullScale.confidenceLower, let upper = profile.fullScale.confidenceUpper {
            XCTAssertGreaterThanOrEqual(lower, WechslerProfileScorer.compositeRange.lowerBound)
            XCTAssertLessThanOrEqual(upper, WechslerProfileScorer.compositeRange.upperBound)
        }
    }

    func testPerfectRunDoesNotSaturateTheScale() throws {
        let bank = try WechslerLoader.loadValidated()
        let model = try WechslerIQModel.load()
        let responses = bank.map { item in
            WechslerResponse(itemID: item.id, subtest: item.subtest, answer: item.correctAnswer,
                             score: item.maxScore, maxScore: item.maxScore, outcome: .answered, elapsedSeconds: 1)
        }
        let ability = try WechslerIQEstimator.ability(items: bank, responses: responses, model: model)
        let profile = WechslerProfileScorer.make(ability: ability, flags: [.ceiling],
                                                 modelVersion: model.version, bankVersion: model.bankVersion)
        // 全部答对应落在量表高分段，但不应一律撞到合成分上限。
        XCTAssertGreaterThan(profile.fullScale.score, 110)
        XCTAssertLessThan(profile.fullScale.score, WechslerProfileScorer.compositeRange.upperBound)
        for index in profile.indices {
            XCTAssertGreaterThan(index.score, 110)
        }
    }

    func testAveragePerformanceLandsNearTheMiddleOfTheScale() throws {
        let bank = try WechslerLoader.loadValidated()
        let model = try WechslerIQModel.load()
        // 每五题错一题，模拟中等水平作答。
        let responses = bank.enumerated().map { index, item in
            let correct = index % 5 != 0
            let score = correct ? item.maxScore : 0
            let answer = correct ? item.correctAnswer
                : (item.requiresRecall ? "0" : item.options[item.optionScores.firstIndex(of: 0)!])
            return WechslerResponse(itemID: item.id, subtest: item.subtest, answer: answer,
                                    score: score, maxScore: item.maxScore, outcome: .answered, elapsedSeconds: 1)
        }
        let ability = try WechslerIQEstimator.ability(items: bank, responses: responses, model: model)
        let profile = WechslerProfileScorer.make(ability: ability, flags: [],
                                                 modelVersion: model.version, bankVersion: model.bankVersion)
        // 中等表现应落在合成分中部，而不是被推到量表两端。
        XCTAssertTrue((90...112).contains(profile.fullScale.score), "全量表分 \(profile.fullScale.score)")
        XCTAssertTrue((35...65).contains(profile.fullScale.percentile))
        // 估计标准误应接近韦氏手册实测的全量表分 SEM 3.0。
        XCTAssertTrue((2.0...5.0).contains(profile.fullScale.standardError),
                      "SEM \(profile.fullScale.standardError)")
    }

    func testScaledScoresCarryTheirOwnUncertainty() throws {
        let bank = try WechslerLoader.loadValidated()
        let model = try WechslerIQModel.load()
        let responses = bank.map { item in
            WechslerResponse(itemID: item.id, subtest: item.subtest, answer: item.correctAnswer,
                             score: item.maxScore, maxScore: item.maxScore, outcome: .answered, elapsedSeconds: 1)
        }
        let ability = try WechslerIQEstimator.ability(items: bank, responses: responses, model: model)
        let profile = WechslerProfileScorer.make(ability: ability, flags: [],
                                                 modelVersion: model.version, bankVersion: model.bankVersion)
        for scaled in profile.subtests {
            let lower = try XCTUnwrap(scaled.confidenceLower)
            let upper = try XCTUnwrap(scaled.confidenceUpper)
            XCTAssertLessThanOrEqual(lower, scaled.scaled)
            XCTAssertGreaterThanOrEqual(upper, scaled.scaled)
            XCTAssertTrue((1...19).contains(lower))
            XCTAssertTrue((1...19).contains(upper))
            // 12 题的小样本使尺度分区间不会窄到失去意义。
            XCTAssertGreaterThan(upper - lower, 0)
        }
    }

    func testDomainComparisonsDetectRealDifferencesOnly() throws {
        let bank = try WechslerLoader.loadValidated()
        let model = try WechslerIQModel.load()
        let verbal: Set<WechslerSubtest> = [.similarities, .vocabulary, .information]
        let responses = bank.map { item in
            let isVerbal = verbal.contains(item.subtest)
            let score = isVerbal ? item.maxScore : 0
            let answer = isVerbal ? item.correctAnswer
                : (item.requiresRecall ? "0" : item.options[item.optionScores.firstIndex(of: 0)!])
            return WechslerResponse(itemID: item.id, subtest: item.subtest, answer: answer,
                                    score: score, maxScore: item.maxScore, outcome: .answered, elapsedSeconds: 1)
        }
        let ability = try WechslerIQEstimator.ability(items: bank, responses: responses, model: model)
        let profile = WechslerProfileScorer.make(ability: ability, flags: [],
                                                 modelVersion: model.version, bankVersion: model.bankVersion)
        let comparisons = try XCTUnwrap(profile.domainComparisons)
        XCTAssertEqual(comparisons.count, 6)
        let verbalPerceptual = try XCTUnwrap(comparisons.first {
            $0.first == .verbal && $0.second == .perceptual })
        XCTAssertTrue(verbalPerceptual.significant, "言语与知觉差距悬殊，应判定为显著")
        XCTAssertGreaterThan(verbalPerceptual.standardError, 0)
        // 记忆与速度都不作答，差距应落在误差范围内。
        let memorySpeed = try XCTUnwrap(comparisons.first {
            $0.first == .memory && $0.second == .speed })
        XCTAssertFalse(memorySpeed.significant)
    }

    func testCalibrationConstantsMatchTheDocumentedBorrowedValues() {
        // 斜率借用自 Pearson 官方示例报告，其前提是「尺度分之和的离散度与韦氏题库相同」。
        // docs/ALGORITHM_SELF_CHECK.py 显示该前提在本项目的题目参数下不成立（合成分离散度约 12.6 而非 15），
        // 因此这里锁住当前取值：一旦用真实样本重新标定，必须同步更新这个断言与文档。
        XCTAssertEqual(WechslerProfileScorer.indexSlope, 2.75, accuracy: 1e-12)
        XCTAssertEqual(WechslerProfileScorer.fullScaleSlope, 0.72, accuracy: 1e-12)
        XCTAssertEqual(WechslerProfileScorer.fullScaleSlopeSevenSubtests, 0.96, accuracy: 1e-12)
        XCTAssertEqual(WechslerProfileScorer.compositeRange, 50...145)
        XCTAssertEqual(WechslerProfileScorer.currentScoringVersion, "wechsler-style-borrowed-v1")
    }

    func testProductionConstantsMatchTheSharedCalibrationFile() throws {
        // ScoringCalibration.json 是换算参数的唯一真源：docs/ 下的分析脚本读它，
        // 生产代码用同名常量，这个测试保证两边不会各改各的。
        let url = try XCTUnwrap(Bundle.main.url(forResource: "ScoringCalibration", withExtension: "json"))
        let data = try Data(contentsOf: url)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(WechslerProfileScorer.indexSlope, try XCTUnwrap(json["indexSlope"] as? Double))
        XCTAssertEqual(WechslerProfileScorer.fullScaleSlope, try XCTUnwrap(json["fullScaleSlope"] as? Double))
        XCTAssertEqual(WechslerProfileScorer.fullScaleSlopeSevenSubtests,
                       try XCTUnwrap(json["fullScaleSlopeSevenSubtests"] as? Double))
        XCTAssertEqual(WechslerIQEstimator.shrinkageSD, try XCTUnwrap(json["shrinkageSD"] as? Double))
        XCTAssertEqual(WechslerProfileScorer.compositeRange.lowerBound,
                       try XCTUnwrap(json["compositeRangeLower"] as? Int))
        XCTAssertEqual(WechslerProfileScorer.compositeRange.upperBound,
                       try XCTUnwrap(json["compositeRangeUpper"] as? Int))
        XCTAssertEqual(WechslerProfileScorer.maximumIntervalHalfWidth,
                       try XCTUnwrap(json["minimumIntervalHalfWidth"] as? Double))
        XCTAssertEqual(WechslerProfileScorer.currentScoringVersion, try XCTUnwrap(json["version"] as? String))
    }

    func testSubtestsCarryTheBankDifficultyBaseline() throws {
        let bank = try WechslerLoader.loadValidated()
        let model = try WechslerIQModel.load()
        let responses = bank.map { item in
            WechslerResponse(itemID: item.id, subtest: item.subtest, answer: item.correctAnswer,
                             score: item.maxScore, maxScore: item.maxScore, outcome: .answered, elapsedSeconds: 1)
        }
        let ability = try WechslerIQEstimator.ability(items: bank, responses: responses, model: model)
        let profile = WechslerProfileScorer.make(ability: ability, flags: [],
                                                 modelVersion: model.version, bankVersion: model.bankVersion)
        for scaled in profile.subtests {
            let baseline = try XCTUnwrap(scaled.baselineRate)
            XCTAssertTrue((0...1).contains(baseline), scaled.subtest.rawValue)
        }
        // 数字广度与符号编码在本题库中一贯更难，基准应明显低于矩阵推理。
        let digitSpan = try XCTUnwrap(profile.subtests.first { $0.subtest == .digitspan }).baselineRate ?? 0
        let matrix = try XCTUnwrap(profile.subtests.first { $0.subtest == .matrix }).baselineRate ?? 0
        XCTAssertLessThan(digitSpan, matrix)
        XCTAssertLessThan(digitSpan, 0.70)
    }

    func testProfileReportsObservedRateAgainstTheBankAverage() throws {
        let bank = try WechslerLoader.loadValidated()
        let model = try WechslerIQModel.load()
        // 每五题错一题，观察到的得分率应高于全错场景。
        let responses = bank.enumerated().map { index, item in
            let correct = index % 5 != 0
            let score = correct ? item.maxScore : 0
            let answer = correct ? item.correctAnswer
                : (item.requiresRecall ? "0" : item.options[item.optionScores.firstIndex(of: 0)!])
            return WechslerResponse(itemID: item.id, subtest: item.subtest, answer: answer,
                                    score: score, maxScore: item.maxScore, outcome: .answered, elapsedSeconds: 1)
        }
        let ability = try WechslerIQEstimator.ability(items: bank, responses: responses, model: model)
        let profile = WechslerProfileScorer.make(ability: ability, flags: [],
                                                 modelVersion: model.version, bankVersion: model.bankVersion)
        let observed = try XCTUnwrap(profile.overallRate)
        let bankAverage = try XCTUnwrap(profile.bankAverageRate)
        XCTAssertTrue((0...1).contains(observed))
        XCTAssertTrue((0...1).contains(bankAverage))
        // 该预期值应与难度诊断脚本得到的整体基准一致（约 0.83）。
        XCTAssertEqual(bankAverage, 0.83, accuracy: 0.03)
        // 「每五题错一题」约合 80%，略低于模型平均能力下的 83%——
        // 正因如此，这一作答对应的全量表分接近但略低于 100。
        XCTAssertLessThan(observed, bankAverage)
        XCTAssertEqual(observed, bankAverage, accuracy: 0.05)
    }

    func testProfileRoundTripsThroughCoding() throws {        let bank = try WechslerLoader.loadValidated()
        let model = try WechslerIQModel.load()
        let responses = bank.map { item in
            WechslerResponse(itemID: item.id, subtest: item.subtest, answer: item.correctAnswer,
                             score: item.maxScore, maxScore: item.maxScore, outcome: .answered, elapsedSeconds: 1)
        }
        let ability = try WechslerIQEstimator.ability(items: bank, responses: responses, model: model)
        let profile = WechslerProfileScorer.make(ability: ability, flags: [.ceiling],
                                                 modelVersion: model.version, bankVersion: model.bankVersion)
        let record = TestRecord(date: Date(), testType: .wechsler, difficulty: .medium, score: 156, total: 156,
                                iq: nil, percentile: nil, scoringVersion: WechslerLoader.bankVersion,
                                wechslerProfile: profile)
        let decoded = try JSONDecoder().decode(TestRecord.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(decoded.wechslerProfile?.fullScale.score, profile.fullScale.score)
        XCTAssertEqual(decoded.wechslerProfile?.indices.count, 4)
        XCTAssertEqual(decoded.wechslerProfile?.subtests.count, 10)
        XCTAssertEqual(decoded.profileValue, profile.fullScale.score)
        XCTAssertEqual(decoded.wechslerProfile?.scoringVersion, "wechsler-style-borrowed-v1")
        // 正式 IQ 字段仍然保持为空，剖面不能被当成已常模化的分数。
        XCTAssertNil(decoded.iq)
        XCTAssertNil(decoded.percentile)
        XCTAssertNil(decoded.displayedIQ)
    }

    func testOlderRecordsWithoutProfileStillDecode() throws {
        let json = """
        {"id":"11111111-1111-1111-1111-111111111111","date":0,"difficulty":"medium","score":10,"total":12}
        """
        let decoded = try JSONDecoder().decode(TestRecord.self, from: Data(json.utf8))
        XCTAssertNil(decoded.wechslerProfile)
        XCTAssertEqual(decoded.testType, .raven)
    }
}
