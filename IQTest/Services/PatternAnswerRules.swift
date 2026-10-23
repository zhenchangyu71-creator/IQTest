import Foundation

/// pattern 类题目的「解析里哪个符号才是答案」规则。
///
/// 规则只有一份，放在资源文件里：Swift 生产代码、单元测试与 Python 生成器
/// 都读它。两处各写一份正则副本曾真的漂移过——Python 端少了兜底规则，
/// 名称型解析的题在答案键写反时完全查不出来。
struct PatternAnswerRule: Decodable {
    let pattern: String
    /// 答案所在的捕获组（1 起）。
    let group: Int
    /// 捕获到的内容要重复几次才算答案（「第四组应有 4 个 X」这类）。
    let repeatCount: Int?

    private enum CodingKeys: String, CodingKey {
        case pattern, group
        case repeatCount = "repeat"
    }
}

enum PatternAnswerRules {
    private struct File: Decodable {
        let rules: [PatternAnswerRule]
    }

    /// 规则文件读一次即可；读失败要报错而不是跳过校验——那正是它要拦的那类错误。
    static let shared: Result<[PatternAnswerRule], Error> = Result { try load() }

    /// 读不到规则文件时不能静默跳过校验。
    static func load() throws -> [PatternAnswerRule] {
        guard let url = Bundle.main.url(forResource: "PatternAnswerRules", withExtension: "json") else {
            throw QuestionLoader.BankError.missingResource
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(File.self, from: data).rules
    }

    /// 从解析里取出真正的答案；匹配不上任何规则时返回 nil（该题不属于可判定的那一类）。
    ///
    /// 答案必须出现在该题的选项里。正则会回溯：某些规则（「以 X Y Z 为一组循环」
    /// 只写了三个符号而正则要四个捕获组）会匹配出空格这类垃圾，选项判据既挡得住它，
    /// 也覆盖箭头与组合符号，不必维护一份会漏符号的白名单。这条约束还让
    /// Swift（ICU）与 Python（re）的正则引擎行为不同时结果一致。
    static func expectedAnswer(explanation: String, options: [String],
                                using rules: [PatternAnswerRule]) -> String? {
        for rule in rules {
            guard let expression = try? NSRegularExpression(pattern: rule.pattern) else { continue }
            let range = NSRange(explanation.startIndex..., in: explanation)
            guard let match = expression.firstMatch(in: explanation, range: range),
                  let matched = Range(match.range(at: rule.group), in: explanation) else { continue }
            let captured = String(explanation[matched])
            let answer = String(repeating: captured, count: rule.repeatCount ?? 1)
            guard options.contains(answer) else { continue }
            return answer
        }
        return nil
    }
}
