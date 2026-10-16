import Foundation

enum Difficulty: String, Codable, CaseIterable, Identifiable {
    case easy = "初级"
    case medium = "中级"
    case hard = "高级"

    var id: String { rawValue }

    /// JSON 数据使用英文键，本地存储使用中文 rawValue，两者都要能解码
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case "easy", Difficulty.easy.rawValue: self = .easy
        case "medium", Difficulty.medium.rawValue: self = .medium
        case "hard", Difficulty.hard.rawValue: self = .hard
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown difficulty: \(raw)"
            )
        }
    }

    /// 每题限时（秒）
    var secondsPerQuestion: Int {
        switch self {
        case .easy: return 60
        case .medium: return 45
        case .hard: return 30
        }
    }

    /// 该难度下的预期平均得分率（用于 IQ 估算）
    var scoreMean: Double {
        switch self {
        case .easy: return 0.70
        case .medium: return 0.55
        case .hard: return 0.40
        }
    }

    var subtitle: String {
        switch self {
        case .easy: return "轻松热身 · 每题 60 秒"
        case .medium: return "标准挑战 · 每题 45 秒"
        case .hard: return "烧脑极限 · 每题 30 秒"
        }
    }

    var icon: String {
        switch self {
        case .easy: return "leaf.fill"
        case .medium: return "bolt.fill"
        case .hard: return "flame.fill"
        }
    }
}

enum TestType: String, Codable, CaseIterable, Identifiable {
    case raven = "瑞文推理"
    case wechsler = "韦氏标准"

    var id: String { rawValue }

    /// JSON 数据使用英文键，本地存储使用中文 rawValue，两者都要能解码
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case "raven", TestType.raven.rawValue: self = .raven
        case "wechsler", TestType.wechsler.rawValue: self = .wechsler
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown test type: \(raw)"
            )
        }
    }

    var shortName: String {
        switch self {
        case .raven: return "瑞文"
        case .wechsler: return "韦氏"
        }
    }

    var subtitle: String {
        switch self {
        case .raven: return "图形矩阵 · 逻辑推理"
        case .wechsler: return "10 分测验 · 标准施测流程"
        }
    }

    var systemImage: String {
        switch self {
        case .raven: return "square.grid.3x3"
        case .wechsler: return "brain.head.profile"
        }
    }

    /// 该体系包含的测评维度（瑞文按维度抽题；韦氏走标准分测验流程，不适用）
    var categories: [QuestionCategory] {
        switch self {
        case .raven: return [.number, .verbal, .logic, .pattern]
        case .wechsler: return []
        }
    }
}

enum QuestionCategory: String, Codable, CaseIterable, Identifiable {
    case number = "数字推理"
    case verbal = "语言类比"
    case logic = "逻辑推理"
    case pattern = "图形规律"
    case comprehension = "言语理解"
    case perceptual = "知觉推理"
    case memory = "工作记忆"
    case processing = "加工速度"

    var id: String { rawValue }

    /// JSON 数据使用英文键，本地存储使用中文 rawValue，两者都要能解码
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case "number", QuestionCategory.number.rawValue: self = .number
        case "verbal", QuestionCategory.verbal.rawValue: self = .verbal
        case "logic", QuestionCategory.logic.rawValue: self = .logic
        case "pattern", QuestionCategory.pattern.rawValue: self = .pattern
        case "comprehension", QuestionCategory.comprehension.rawValue: self = .comprehension
        case "perceptual", QuestionCategory.perceptual.rawValue: self = .perceptual
        case "memory", QuestionCategory.memory.rawValue: self = .memory
        case "processing", QuestionCategory.processing.rawValue: self = .processing
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown category: \(raw)"
            )
        }
    }

    var systemImage: String {
        switch self {
        case .number: return "number"
        case .verbal: return "textformat"
        case .logic: return "brain.head.profile"
        case .pattern: return "square.on.square"
        case .comprehension: return "text.book.closed"
        case .perceptual: return "square.grid.3x3"
        case .memory: return "memorychip"
        case .processing: return "bolt.fill"
        }
    }
}

struct Question: Codable, Identifiable, Equatable {
    let id: Int
    let testType: TestType
    let difficulty: Difficulty
    let category: QuestionCategory
    let prompt: String
    let options: [String]
    let correctIndex: Int
    let explanation: String

    /// 旧版题库没有 testType 字段，缺省视为瑞文
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        testType = try container.decodeIfPresent(TestType.self, forKey: .testType) ?? .raven
        difficulty = try container.decode(Difficulty.self, forKey: .difficulty)
        category = try container.decode(QuestionCategory.self, forKey: .category)
        prompt = try container.decode(String.self, forKey: .prompt)
        options = try container.decode([String].self, forKey: .options)
        correctIndex = try container.decode(Int.self, forKey: .correctIndex)
        explanation = try container.decode(String.self, forKey: .explanation)
    }
}
