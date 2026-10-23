import XCTest
@testable import IQTest

/// 选项顺序与答案位置。
///
/// 题库里正确选项的位置并不均匀：图形规律类约四成落在第一个，语言类比类约四成。
/// 按题库原始顺序显示选项，等于把答案位置告诉用户——一直选第一个就能多得近两分。
/// 抽题后必须打乱每题的选项顺序。
@MainActor
final class QuestionOptionOrderTests: XCTestCase {

    func testShuffledOptionsKeepsTheSameAnswerAndRemovesThePositionBias() throws {
        let bank = try QuestionLoader.loadValidated()
        XCTAssertFalse(bank.isEmpty)
        var counts = [Int](repeating: 0, count: 4)
        for question in bank {
            for _ in 0..<5 {
                let shuffled = question.shuffledOptions()
                XCTAssertEqual(shuffled.options[shuffled.correctIndex],
                               question.options[question.correctIndex],
                               "题 \(question.id)：打乱后正确选项必须还是同一个")
                XCTAssertEqual(Set(shuffled.options), Set(question.options),
                               "题 \(question.id)：选项集合不变")
                counts[shuffled.correctIndex] += 1
            }
        }
        // 均匀时每个位置约 540 次，标准差约 20。某个位置超过 1500（48 个标准差）
        // 说明答案位置仍在泄露——那正是「一直选第一个」能白拿分的条件。
        for (index, count) in counts.enumerated() {
            XCTAssertLessThan(count, 1500, "位置 \(index) 出现过多：\(counts)")
        }
    }

    func testEachRoundShufflesOptionsAndKeepsAnswersIntact() throws {
        let bank = try QuestionLoader.loadValidated()
        let byID = Dictionary(uniqueKeysWithValues: bank.map { ($0.id, $0) })
        let vm = QuizViewModel()
        vm.testType = .raven
        vm.difficulty = .medium
        vm.start()
        XCTAssertEqual(vm.questions.count, 12)
        for question in vm.questions {
            let original = try XCTUnwrap(byID[question.id])
            XCTAssertEqual(question.options[question.correctIndex],
                           original.options[original.correctIndex],
                           "题 \(question.id)：抽题后正确选项必须还是同一个")
            XCTAssertEqual(Set(question.options), Set(original.options))
        }
    }

    func testAnsweringTheCorrectOptionStillScores() {
        // 打乱后判分要跟着新顺序走：选中正确选项仍得 1 分，选错得 0 分。
        let vm = QuizViewModel()
        vm.testType = .raven
        vm.difficulty = .easy
        vm.start()
        guard let question = vm.currentQuestion else {
            return XCTFail("应当有一道题")
        }
        vm.recordAnswer(question.correctIndex, questionToken: vm.questionToken)
        XCTAssertEqual(vm.score, 1, "选中正确选项应得 1 分")
    }
}
