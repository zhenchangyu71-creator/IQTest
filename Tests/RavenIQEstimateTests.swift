import XCTest
@testable import IQTest

/// 瑞文模块经验量尺输出与估计区间的测试。
final class RavenIQEstimateTests: XCTestCase {

    func testWilsonIntervalBracketsTheObservedRate() {
        for successes in 0...12 {
            let (lower, upper) = IQScale.wilsonInterval(successes: successes, trials: 12)
            XCTAssertLessThanOrEqual(lower, upper)
            XCTAssertLessThanOrEqual(lower, Double(successes) / 12 + 1e-9)
            XCTAssertGreaterThanOrEqual(upper, Double(successes) / 12 - 1e-9)
        }
    }

    func testWilsonIntervalStaysValidAtExtremeRates() {
        // 正态近似在全错时会退化成零宽区间，Wilson 不会。
        let (low, high) = IQScale.wilsonInterval(successes: 0, trials: 12)
        XCTAssertEqual(low, 0, accuracy: 1e-9)
        XCTAssertGreaterThan(high, 0)
        XCTAssertLessThan(high, 0.3)
        let (lowPerfect, highPerfect) = IQScale.wilsonInterval(successes: 12, trials: 12)
        XCTAssertEqual(highPerfect, 1, accuracy: 1e-9)
        XCTAssertLessThan(lowPerfect, 1)
    }

    func testRavenEstimateCarriesItsInterval() throws {
        let estimate = try XCTUnwrap(RavenIQEstimate.make(score: 9, total: 12, difficulty: .medium))
        let lower = try XCTUnwrap(estimate.confidenceLower)
        let upper = try XCTUnwrap(estimate.confidenceUpper)
        XCTAssertLessThanOrEqual(lower, estimate.value)
        XCTAssertGreaterThanOrEqual(upper, estimate.value)
        XCTAssertTrue(RavenIQEstimate.valueRange.contains(lower))
        XCTAssertTrue(RavenIQEstimate.valueRange.contains(upper))
    }

    func testRavenIntervalNarrowsWithMoreItems() throws {
        // 同样的正确比例，题量越多区间越窄。
        let few = try XCTUnwrap(RavenIQEstimate.make(score: 9, total: 12, difficulty: .medium))
        let many = try XCTUnwrap(RavenIQEstimate.make(score: 30, total: 40, difficulty: .medium))
        let fewLower = try XCTUnwrap(few.confidenceLower)
        let fewUpper = try XCTUnwrap(few.confidenceUpper)
        let manyLower = try XCTUnwrap(many.confidenceLower)
        let manyUpper = try XCTUnwrap(many.confidenceUpper)
        XCTAssertLessThan(manyUpper - manyLower, fewUpper - fewLower)
    }

    func testRavenEstimateRejectsInvalidScores() {
        XCTAssertNil(RavenIQEstimate.make(score: -1, total: 12, difficulty: .medium))
        XCTAssertNil(RavenIQEstimate.make(score: 13, total: 12, difficulty: .medium))
        XCTAssertNil(RavenIQEstimate.make(score: 0, total: 0, difficulty: .medium))
    }

    func testOlderRavenRecordsWithoutIntervalStillDecode() throws {
        let json = """
        {"value":100,"modelVersion":"raven-heuristic-v1","bankVersion":"old","ageAdjusted":false,"calibrationStatus":"heuristic"}
        """
        let decoded = try JSONDecoder().decode(RavenIQEstimate.self, from: Data(json.utf8))
        XCTAssertNil(decoded.confidenceLower)
        XCTAssertNil(decoded.confidenceUpper)
        XCTAssertEqual(decoded.value, 100)
    }
}
