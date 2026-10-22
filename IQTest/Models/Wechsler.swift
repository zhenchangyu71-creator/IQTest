import Foundation

// MARK: - 分测验（本题库的固定练习顺序，不作为官方施测规则）

enum WechslerSubtest: String, Codable, CaseIterable, Identifiable {
    case block = "积木"
    case similarities = "类同"
    case digitspan = "数字广度"
    case matrix = "矩阵推理"
    case vocabulary = "词汇"
    case arithmetic = "算术"
    case symbolsearch = "符号搜索"
    case visualpuzzle = "视觉拼图"
    case information = "常识"
    case coding = "符号编码"

    var id: String { rawValue }

    /// JSON 数据使用英文键，本地存储使用中文 rawValue，两者都要能解码
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case "block", WechslerSubtest.block.rawValue: self = .block
        case "similarities", WechslerSubtest.similarities.rawValue: self = .similarities
        case "digitspan", WechslerSubtest.digitspan.rawValue: self = .digitspan
        case "matrix", WechslerSubtest.matrix.rawValue: self = .matrix
        case "vocabulary", WechslerSubtest.vocabulary.rawValue: self = .vocabulary
        case "arithmetic", WechslerSubtest.arithmetic.rawValue: self = .arithmetic
        case "symbolsearch", WechslerSubtest.symbolsearch.rawValue: self = .symbolsearch
        case "visualpuzzle", WechslerSubtest.visualpuzzle.rawValue: self = .visualpuzzle
        case "information", WechslerSubtest.information.rawValue: self = .information
        case "coding", WechslerSubtest.coding.rawValue: self = .coding
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown subtest: \(raw)"
            )
        }
    }

    /// 所属练习领域（四类）
    var domain: WechslerDomain {
        switch self {
        case .similarities, .vocabulary, .information: return .verbal
        case .block, .matrix, .visualpuzzle: return .perceptual
        case .digitspan, .arithmetic: return .memory
        case .symbolsearch, .coding: return .speed
        }
    }

    /// 每题限时（秒）。数字广度的限时为回忆阶段；呈现阶段使用题目的 displaySeconds
    var timeLimit: Int {
        switch self {
        case .similarities, .vocabulary, .information, .arithmetic: return 60
        case .block, .matrix, .visualpuzzle: return 45
        case .digitspan: return 15
        case .symbolsearch, .coding: return 5
        }
    }

    /// 自编练习每题满分（言语题按 0/1/2 计分）
    var maxPointsPerItem: Int {
        switch self {
        case .similarities, .vocabulary, .information: return 2
        default: return 1
        }
    }
}

enum WechslerDomain: String, Codable, CaseIterable, Identifiable {
    case verbal = "言语理解"
    case perceptual = "知觉推理"
    case memory = "工作记忆"
    case speed = "加工速度"

    var id: String { rawValue }

    var shortName: String {
        switch self {
        case .verbal: return "言语"
        case .perceptual: return "知觉"
        case .memory: return "记忆"
        case .speed: return "速度"
        }
    }

    var subtests: [WechslerSubtest] {
        WechslerSubtest.allCases.filter { $0.domain == self }
    }
}

// MARK: - 自编练习题库（未常模化）

struct WechslerItem: Codable, Identifiable {
    enum RecallRule: String, Codable { case forward, backward, ascending }
    let id: String
    let order: Int
    let subtest: WechslerSubtest
    let prompt: String
    let options: [String]
    let optionScores: [Int]
    let explanation: String
    let presentation: String?
    let stimulus: String?
    let displaySeconds: Int?
    let recallRule: RecallRule?

    var maxScore: Int { optionScores.max() ?? 0 }
    var requiresRecall: Bool { presentation == "digits" }
    var correctAnswer: String {
        zip(options, optionScores).first { $0.1 == maxScore }?.0 ?? ""
    }

    init(id: String, order: Int = 0, subtest: WechslerSubtest, prompt: String,
         options: [String], optionScores: [Int], explanation: String,
         presentation: String? = nil, stimulus: String? = nil, displaySeconds: Int? = nil,
         recallRule: RecallRule? = nil) {
        self.id = id
        self.order = order
        self.subtest = subtest
        self.prompt = prompt
        self.options = options
        self.optionScores = optionScores
        self.explanation = explanation
        self.presentation = presentation
        self.stimulus = stimulus
        self.displaySeconds = displaySeconds
        self.recallRule = recallRule
    }

    enum CodingKeys: String, CodingKey {
        case id, subtest, prompt, options, optionScores, explanation, presentation, stimulus, displaySeconds, recallRule
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        subtest = try c.decode(WechslerSubtest.self, forKey: .subtest)
        prompt = try c.decode(String.self, forKey: .prompt)
        options = try c.decode([String].self, forKey: .options)
        optionScores = try c.decode([Int].self, forKey: .optionScores)
        explanation = try c.decode(String.self, forKey: .explanation)
        presentation = try c.decodeIfPresent(String.self, forKey: .presentation)
        stimulus = try c.decodeIfPresent(String.self, forKey: .stimulus)
        displaySeconds = try c.decodeIfPresent(Int.self, forKey: .displaySeconds)
        recallRule = try c.decodeIfPresent(RecallRule.self, forKey: .recallRule)
        order = 0
    }

    /// 根据明确的回忆规则从刺激独立求解，避免错误答案键污染计分。
    var expectedRecall: String? {
        guard let stimulus, let digits = Self.normalizedDigits(stimulus), !digits.isEmpty,
              let recallRule else { return nil }
        switch recallRule {
        case .forward: return digits
        case .backward: return String(digits.reversed())
        case .ascending: return String(digits.sorted())
        }
    }

    /// 只接受数字和空白，保留前导零；错误序列得零分，非法输入不提交。
    func recallScore(for answer: String) -> Int? {
        guard requiresRecall, let expectedRecall, let input = Self.normalizedDigits(answer), !input.isEmpty else { return nil }
        return input == expectedRecall ? maxScore : 0
    }

    private static func normalizedDigits(_ value: String) -> String? {
        var result = ""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 48...57: result.unicodeScalars.append(scalar)
            case 65296...65305: result.append(String(scalar.value - 65296))
            default:
                guard CharacterSet.whitespacesAndNewlines.contains(scalar) else { return nil }
            }
        }
        return result
    }
}

enum WechslerLoader {
    static let bankVersion = "practice-2026-10-22-v4"
    static let scoringNotice = "本结果采用韦氏风格的量表分换算结构，但未经人群常模校准，也不是正式韦氏 IQ；年龄仅作记录、未参与换算，区间仅反映本次测量误差。"

    enum BankError: LocalizedError {
        case missingResource
        case invalid(String)
        var errorDescription: String? {
            switch self {
            case .missingResource: return "无法读取练习题库，请重新安装应用后重试。"
            case .invalid(let reason): return "题库校验失败：\(reason)"
            }
        }
    }

    static func loadValidated(_ questionSet: WechslerQuestionSet = .a) throws -> [WechslerItem] {
        guard let url = Bundle.main.url(forResource: questionSet.bankResource, withExtension: "json") else {
            throw BankError.missingResource
        }
        return try decode(Data(contentsOf: url))
    }

    static func load() -> [WechslerItem] { (try? loadValidated()) ?? [] }

    static func decode(_ data: Data) throws -> [WechslerItem] {
        let items = try JSONDecoder().decode([WechslerItem].self, from: data)
        try validate(items)
        var orders: [WechslerSubtest: Int] = [:]
        return items.map { item in
            let order = (orders[item.subtest] ?? 0) + 1
            orders[item.subtest] = order
            return WechslerItem(id: item.id, order: order, subtest: item.subtest,
                                prompt: item.prompt, options: item.options, optionScores: item.optionScores,
                                explanation: item.explanation, presentation: item.presentation,
                                stimulus: item.stimulus, displaySeconds: item.displaySeconds, recallRule: item.recallRule)
        }
    }

    static func validate(_ items: [WechslerItem]) throws {
        guard Set(items.map(\.id)).count == items.count else { throw BankError.invalid("存在重复题号") }
        for subtest in WechslerSubtest.allCases {
            guard items.filter({ $0.subtest == subtest }).count >= 3 else {
                throw BankError.invalid("\(subtest.rawValue)不足三题")
            }
        }
        for item in items {
            guard !item.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !item.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !item.explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  item.options.count >= 2, item.options.count == item.optionScores.count,
                  Set(item.options).count == item.options.count,
                  item.options.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
                  item.optionScores.allSatisfy({ (0...item.subtest.maxPointsPerItem).contains($0) }),
                  item.maxScore == item.subtest.maxPointsPerItem,
                  item.optionScores.filter({ $0 == item.maxScore }).count == 1,
                  item.optionScores.contains(0) else { throw BankError.invalid("\(item.id)选项或评分不完整") }
            guard item.presentation == nil || item.presentation == "digits" else {
                throw BankError.invalid("\(item.id)呈现方式不支持")
            }
            if item.subtest == .digitspan {
                guard item.requiresRecall, let stimulus = item.stimulus, !stimulus.isEmpty,
                      let seconds = item.displaySeconds, (1...30).contains(seconds),
                      item.recallScore(for: item.correctAnswer) == item.maxScore,
                      stimulus.filter({ !$0.isWhitespace }).count == item.correctAnswer.filter({ !$0.isWhitespace }).count else {
                    throw BankError.invalid("\(item.id)数字刺激不完整")
                }
            } else if item.requiresRecall { throw BankError.invalid("\(item.id)分测验与呈现方式不匹配") }
        }
    }
}

struct WechslerResponse: Codable, Identifiable {
    enum Outcome: String, Codable { case answered, timedOut, interrupted }
    var id: String { itemID }
    let itemID: String
    let subtest: WechslerSubtest
    let answer: String?
    let score: Int
    let maxScore: Int
    let outcome: Outcome
    let elapsedSeconds: Double
}

enum WechslerScoring {
    struct SubtestResult: Identifiable {
        var id: WechslerSubtest { subtest }
        let subtest: WechslerSubtest
        let raw: Int
        let maxRaw: Int
        let answered: Int
        let total: Int
        let timedOut: Int
        let interrupted: Int
        var percentage: Int { WechslerScoring.percentage(raw: raw, maxRaw: maxRaw) }
    }

    /// 仅为题目得分率，不是人群百分位或量表分。
    static func percentage(raw: Int, maxRaw: Int) -> Int {
        guard maxRaw > 0 else { return 0 }
        return Int((Double(min(max(raw, 0), maxRaw)) / Double(maxRaw) * 100).rounded())
    }

    static func results(items: [WechslerItem], responses: [WechslerResponse]) -> [SubtestResult] {
        WechslerSubtest.allCases.map { subtest in
            let pool = items.filter { $0.subtest == subtest }
            let attempts = responses.filter { $0.subtest == subtest }
            let interrupted = attempts.filter { $0.outcome == .interrupted }
            let excluded = Set(interrupted.map(\.itemID))
            return SubtestResult(subtest: subtest, raw: attempts.reduce(0) { $0 + $1.score },
                                 maxRaw: pool.filter { !excluded.contains($0.id) }.reduce(0) { $0 + $1.maxScore },
                                 answered: attempts.count - interrupted.count, total: pool.count,
                                 timedOut: attempts.filter { $0.outcome == .timedOut }.count,
                                 interrupted: interrupted.count)
        }
    }
}
