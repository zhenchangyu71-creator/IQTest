import Foundation

enum QuestionLoader {
    enum BankError: LocalizedError {
        case missingResource, invalid(String)
        var errorDescription: String? {
            switch self {
            case .missingResource: return "无法读取推理题库，请重新安装应用后重试。"
            case .invalid(let reason): return "推理题库校验失败：\(reason)"
            }
        }
    }

    static func load() -> [Question] { (try? loadValidated()) ?? [] }

    static func loadValidated() throws -> [Question] {
        guard let url = Bundle.main.url(forResource: "Questions", withExtension: "json") else {
            throw BankError.missingResource
        }
        return try decode(Data(contentsOf: url))
    }

    static func decode(_ data: Data) throws -> [Question] {
        let bank = try JSONDecoder().decode([Question].self, from: data)
        try validate(bank)
        return bank
    }

    static func validate(_ bank: [Question]) throws {
        guard Set(bank.map(\.id)).count == bank.count else { throw BankError.invalid("存在重复题号") }
        // 题干去掉所有空白后比较：只去首尾的话，「X Y X Y X ？」与「X Y X Y X ？」
        // 会被当成两道不同的题，而它们其实是同一道题的两份副本——同一轮会同时抽到。
        let prompts = bank.map { $0.prompt.split(whereSeparator: { $0.isWhitespace }).joined() }
        guard Set(prompts).count == bank.count else { throw BankError.invalid("存在重复题干") }
        for item in bank {
            let text = [item.prompt, item.explanation] + item.options
            guard item.id > 0, item.testType == .raven, TestType.raven.categories.contains(item.category),
                  item.options.count >= 2, Set(item.options).count == item.options.count,
                  item.options.indices.contains(item.correctIndex),
                  text.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                throw BankError.invalid("题号 \(item.id) 的题干、选项或答案不完整")
            }
        }
        for difficulty in Difficulty.allCases {
            for category in TestType.raven.categories {
                guard bank.filter({ $0.difficulty == difficulty && $0.category == category }).count >= 3 else {
                    throw BankError.invalid("\(difficulty.rawValue)的\(category.rawValue)不足三题")
                }
            }
        }
    }
}
