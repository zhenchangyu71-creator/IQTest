import Foundation

// MARK: - 分测验（按 WAIS 标准施测顺序排列）

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

    /// 所属指数（四大领域）
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

    /// 每题满分（言语理解分测验按 0/1/2 计分）
    var maxPointsPerItem: Int {
        switch self {
        case .similarities, .vocabulary, .information: return 2
        default: return 1
        }
    }
}

enum WechslerDomain: String, CaseIterable, Identifiable {
    case verbal = "言语理解指数"
    case perceptual = "知觉推理指数"
    case memory = "工作记忆指数"
    case speed = "加工速度指数"

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

// MARK: - 题目

struct WechslerItem: Codable, Identifiable {
    let id = UUID()
    /// 分测验内序号（文件内已按难度递增排列）
    let order: Int
    let subtest: WechslerSubtest
    let prompt: String
    let options: [String]
    /// 每个选项的得分（0/1/2），与 options 一一对应
    let optionScores: [Int]
    /// 特殊呈现方式：digits = 先呈现数字刺激再回忆
    let presentation: String?
    /// 数字广度：刺激内容
    let stimulus: String?
    /// 数字广度：刺激呈现秒数
    let displaySeconds: Int?

    enum CodingKeys: String, CodingKey {
        case order, subtest, prompt, options, optionScores, presentation, stimulus, displaySeconds
    }

    init(order: Int, subtest: WechslerSubtest, prompt: String, options: [String],
         optionScores: [Int], presentation: String? = nil,
         stimulus: String? = nil, displaySeconds: Int? = nil) {
        self.order = order
        self.subtest = subtest
        self.prompt = prompt
        self.options = options
        self.optionScores = optionScores
        self.presentation = presentation
        self.stimulus = stimulus
        self.displaySeconds = displaySeconds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        subtest = try c.decode(WechslerSubtest.self, forKey: .subtest)
        prompt = try c.decode(String.self, forKey: .prompt)
        options = try c.decode([String].self, forKey: .options)
        optionScores = try c.decode([Int].self, forKey: .optionScores)
        presentation = try c.decodeIfPresent(String.self, forKey: .presentation)
        stimulus = try c.decodeIfPresent(String.self, forKey: .stimulus)
        displaySeconds = try c.decodeIfPresent(Int.self, forKey: .displaySeconds)
        order = 0 // 由 loader 按文件顺序填充
    }
}

enum WechslerLoader {
    /// 返回按施测顺序、分测验内按难度递增排列的题目
    static func load() -> [WechslerItem] {
        guard let url = Bundle.main.url(forResource: "Wechsler", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            assertionFailure("Wechsler.json not found in bundle")
            return []
        }
        do {
            let items = try JSONDecoder().decode([WechslerItem].self, from: data)
            var orderInSubtest: [WechslerSubtest: Int] = [:]
            return items.map { item in
                let next = (orderInSubtest[item.subtest] ?? 0) + 1
                orderInSubtest[item.subtest] = next
                return WechslerItem(
                    order: next, subtest: item.subtest, prompt: item.prompt,
                    options: item.options, optionScores: item.optionScores,
                    presentation: item.presentation, stimulus: item.stimulus,
                    displaySeconds: item.displaySeconds
                )
            }
        } catch {
            assertionFailure("Failed to decode Wechsler.json: \(error)")
            return []
        }
    }
}

// MARK: - 计分（简化常模）

enum WechslerScoring {
    struct SubtestResult {
        let subtest: WechslerSubtest
        let raw: Int
        /// 量表分（M=10，SD=3，范围 1...19）
        let scaled: Int
    }

    /// 原始分 → 量表分：线性映射，满分约 16 分，半数约 10 分
    static func scaled(raw: Int, maxRaw: Int) -> Int {
        guard maxRaw > 0 else { return 10 }
        let value = 10.0 + (Double(raw) / Double(maxRaw) - 0.5) * 12.0
        return min(19, max(1, Int(value.rounded())))
    }

    /// 量表分均值 → 指数/FSIQ（M=100，SD=15）
    static func index(avgScaled: Double) -> Int {
        let value = 100.0 + (avgScaled - 10.0) * 5.0
        return min(145, max(55, Int(value.rounded())))
    }

    /// 正态分布百分位
    static func percentile(of iq: Int) -> Int {
        let z = Double(iq - 100) / 15.0
        let cdf = 0.5 * (1.0 + erf(z / sqrt(2.0)))
        return Int((cdf * 100).rounded())
    }
}
