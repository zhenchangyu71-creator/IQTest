import XCTest
@testable import IQTest

/// 导出的真实作答数据能不能被用来标定。
///
/// 真实样本标定的入口是 `docs/calibration_export.py`：它从导出的 JSON 里读
/// 逐题作答，按题号去匹配题目参数，再算尺度分之和的离散度。
/// 链上任何一环对不上（少题、题号匹配不上、分数与总分不一致），
/// 标定出来的斜率就是错的——而这不会在应用里报任何错。
///
/// 此前导出的测试用的是手工构造的假记录，真实跑一遍练习产生的数据从未被核对过。
@MainActor
final class ExportIntegrityTests: XCTestCase {
    private final class Clock { var time: TimeInterval = 1000 }

    /// 跑完一整轮韦氏练习（120 题），返回导出的记录。
    private func completedExport(fullScore: Bool) throws -> TestRecord {
        let clock = Clock()
        var records: [TestRecord] = []
        let vm = WechslerViewModel(now: { clock.time }, saveRecord: { records.append($0) })
        vm.start(questionSet: .a)
        for _ in 0..<120 {
            guard vm.phase != .finished else { break }
            if vm.phase == .briefing {
                vm.answerTutorial(vm.instructions.sample.correctAnswer)
                vm.beginSubtest()
            }
            guard let item = vm.currentItem else { break }
            if vm.phase == .stimulus {
                clock.time += Double(item.displaySeconds ?? 4)
                vm.tick()
            }
            if item.requiresRecall {
                vm.submitRecall(fullScore ? item.correctAnswer : "0", for: item.id)
            } else if let option = vm.presentedOptions.first(where: { $0.score == (fullScore ? item.maxScore : 0) }) {
                vm.choose(optionID: option.id, for: item.id)
            }
        }
        XCTAssertEqual(vm.phase, .finished)
        return try XCTUnwrap(records.first, "应当保存一条记录")
    }

    func testExportedResponsesAreCompleteAndSelfConsistent() throws {
        let record = try completedExport(fullScore: true)
        let responses = try XCTUnwrap(record.responses, "导出必须带逐题作答")
        XCTAssertEqual(responses.count, 120, "一轮完整练习应有 120 条作答")
        XCTAssertEqual(record.plannedItemCount, 120)
        XCTAssertEqual(Set(responses.map(\.itemID)).count, responses.count, "题号不能重复")

        // 每条作答的分数不能超过该题满分，总分与逐题分数必须对得上。
        for response in responses {
            XCTAssertGreaterThanOrEqual(response.score, 0)
            XCTAssertLessThanOrEqual(response.score, response.maxScore, response.itemID)
        }
        XCTAssertEqual(record.score, responses.reduce(0) { $0 + $1.score })
        XCTAssertEqual(record.total, responses.reduce(0) { $0 + $1.maxScore })

        // 逐题快照必须与作答一一对应：标定脚本靠它复核每道题。
        let items = try XCTUnwrap(record.reviewItems)
        XCTAssertEqual(items.count, responses.count)
        XCTAssertEqual(Set(items.map(\.id)), Set(responses.map(\.itemID)))
    }

    func testEveryExportedItemIDExistsInTheBank() throws {
        // 标定脚本按题号匹配题目参数；匹配不上的题会被静默丢掉，
        // 离散度估计随之偏掉，而应用里不会报错。
        let record = try completedExport(fullScore: false)
        let responses = try XCTUnwrap(record.responses)
        let bank = try WechslerLoader.loadValidated(.a)
        let known = Set(bank.map(\.id))
        for response in responses {
            XCTAssertTrue(known.contains(response.itemID),
                          "导出的题号 \(response.itemID) 不在题库里，标定时会被丢掉")
        }
    }

    func testExportedJSONRoundTripsAndKeepsTheResponses() throws {
        let record = try completedExport(fullScore: true)
        let data = try RecordExport.encode([record], at: Date(timeIntervalSince1970: 2000))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(RecordExport.self, from: data)
        let exported = try XCTUnwrap(decoded.records.first)
        XCTAssertEqual(exported.responses?.count, 120)
        XCTAssertEqual(exported.reviewItems?.count, 120)
        XCTAssertEqual(exported.score, record.score)
        XCTAssertEqual(exported.total, record.total)
        XCTAssertEqual(exported.responses?.map(\.itemID), record.responses?.map(\.itemID))
    }
}
