import XCTest
@testable import IQTest

final class HistoryExportTests: XCTestCase {
    func testFiltersCombineModuleAndCompletionAndKeepNewestFirst() {
        let raven = TestRecord(date: Date(timeIntervalSince1970: 1), testType: .raven, difficulty: .medium,
                               score: 2, total: 12, iq: nil, percentile: nil)
        let early = TestRecord(date: Date(timeIntervalSince1970: 3), testType: .raven, difficulty: .medium,
                               score: 1, total: 2, iq: nil, percentile: nil, completion: .endedEarly)
        let wechsler = TestRecord(date: Date(timeIntervalSince1970: 2), testType: .wechsler, difficulty: .medium,
                                  score: 90, total: 156, iq: nil, percentile: nil, questionSet: .b)
        let records = [raven, early, wechsler]
        XCTAssertEqual(HistoryFilter().apply(to: records).map(\.id), [early.id, wechsler.id, raven.id])
        XCTAssertEqual(HistoryFilter(module: .raven, completion: .endedEarly).apply(to: records).map(\.id), [early.id])
        XCTAssertEqual(HistoryFilter(module: .wechsler, completion: .completed).apply(to: records).map(\.id), [wechsler.id])
        XCTAssertTrue(HistoryFilter(module: .wechsler, completion: .endedEarly).apply(to: records).isEmpty)
    }

    func testJSONExportKeepsOriginalScoresIDsVersionsAndIncompleteStatus() throws {
        let record = TestRecord(date: Date(timeIntervalSince1970: 1000), testType: .wechsler, difficulty: .medium,
                                score: 1, total: 2, iq: nil, percentile: nil, age: 25,
                                scoringVersion: "bank-fixture", completion: .endedEarly, plannedItemCount: 120, questionSet: .b)
        let data = try RecordExport.encode([record], at: Date(timeIntervalSince1970: 2000))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["formatVersion"] as? Int, 1)
        XCTAssertEqual(object["exportedAt"] as? String, "1970-01-01T00:33:20Z")
        let rows = try XCTUnwrap(object["records"] as? [[String: Any]])
        XCTAssertEqual(rows.count, 1)
        XCTAssertNil(rows[0]["iq"])
        XCTAssertNil(rows[0]["percentile"])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(RecordExport.self, from: data)
        XCTAssertEqual(decoded.records.first?.id, record.id)
        XCTAssertEqual(decoded.records.first?.score, 1)
        XCTAssertEqual(decoded.records.first?.date, record.date)
        XCTAssertEqual(decoded.records.first?.questionSet, .b)
        XCTAssertEqual(decoded.records.first?.completion, .endedEarly)
        XCTAssertEqual(decoded.records.first?.scoringVersion, "bank-fixture")
    }
}
