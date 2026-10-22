import Foundation

/// 当次题目内容和评分的只读快照。历史回顾不依赖后续版本题库。
struct RecordedItem: Codable, Identifiable {
    enum Outcome: String, Codable { case answered, timedOut, interrupted }
    struct Option: Codable { let text: String; let score: Int }
    let id: String
    let group: String
    let prompt: String
    let stimulus: String?
    let recallRule: WechslerItem.RecallRule?
    let displaySeconds: Int?
    let options: [Option]
    let answer: String?
    let correctAnswer: String
    let explanation: String
    let score: Int
    let maxScore: Int
    let outcome: Outcome
    let elapsedSeconds: Double

    static func raven(_ question: Question, selected: Int?, elapsedSeconds: Double) -> Self {
        Self(id: String(question.id), group: question.category.rawValue, prompt: question.prompt,
             stimulus: nil, recallRule: nil, displaySeconds: nil,
             options: question.options.enumerated().map { Option(text: $0.element, score: $0.offset == question.correctIndex ? 1 : 0) },
             answer: selected.map { question.options[$0] }, correctAnswer: question.options[question.correctIndex],
             explanation: question.explanation, score: selected == question.correctIndex ? 1 : 0,
             maxScore: 1, outcome: selected == nil ? .timedOut : .answered, elapsedSeconds: elapsedSeconds)
    }
}
