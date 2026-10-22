import Foundation

/// 在人为设定的坐标上输出 IQ 量尺分数；没有人群常模或韦氏对照效度。
struct WechslerIQEstimate: Codable {
    enum CalibrationStatus: String, Codable { case heuristic }
    enum Flag: String, Codable {
        case ceiling, floor, timeouts
        var message: String {
            switch self {
            case .ceiling: return "全部答对，出现天花板效应，当前题库不足以区分更高能力水平。"
            case .floor: return "全部未得分，出现地板效应，不宜将此估算用于判断低能力水平。"
            case .timeouts: return "存在超时项目，模型按零分处理；设备操作和注意状态也可能影响结果。"
            }
        }
    }
    let value: Int
    let theta: Double
    let modelVersion: String
    let bankVersion: String
    let calibrationStatus: CalibrationStatus
    let ageAdjusted: Bool
    let answeredCount: Int
    let timedOutCount: Int
    let flags: [Flag]
}

struct WechslerIQModel: Codable {
    struct ItemParameter: Codable {
        let itemID: String
        let discrimination: Double
        /// 二分类一个阈值；存在 0/1/2 三种评分时为两个递增阈值。
        let thresholds: [Double]
    }
    let version: String
    let bankVersion: String
    let calibrationStatus: WechslerIQEstimate.CalibrationStatus
    let items: [ItemParameter]

    static func load(_ questionSet: WechslerQuestionSet = .a) throws -> Self {
        guard let url = Bundle.main.url(forResource: questionSet.modelResource, withExtension: "json") else {
            throw WechslerIQEstimator.EstimationError.invalidModel("未找到估算参数文件")
        }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }

    func validate(for bank: [WechslerItem]) throws {
        guard bankVersion == WechslerLoader.bankVersion, !version.isEmpty,
              Set(items.map(\.itemID)).count == items.count,
              Set(bank.map(\.id)).count == bank.count,
              // 模型必须覆盖本轮要做的每一道题：缺参数的那道题会被静默排除出估计。
              // 模型可以比本轮题量大（题库全量 240 项，本轮只做其中一部分）。
              Set(bank.map(\.id)).isSubset(of: Set(items.map(\.itemID))) else {
            throw WechslerIQEstimator.EstimationError.invalidModel("模型版本或题号与本题库不匹配")
        }
        let byID = Dictionary(uniqueKeysWithValues: bank.map { ($0.id, $0) })
        // 只校验本轮用到的题目的参数。题库可以大于本轮题量，
        // 未被抽到的题留到下一轮抽中时再校验。
        for parameter in items where byID[parameter.itemID] != nil {
            guard let question = byID[parameter.itemID],
                  parameter.discrimination.isFinite, (0.1...3).contains(parameter.discrimination),
                  parameter.thresholds.count == (question.optionScores.contains(1) && question.maxScore == 2 ? 2 : 1),
                  parameter.thresholds.allSatisfy({ $0.isFinite && (-5...5).contains($0) }),
                  zip(parameter.thresholds, parameter.thresholds.dropFirst()).allSatisfy({ $0 < $1 }) else {
                throw WechslerIQEstimator.EstimationError.invalidModel("\(parameter.itemID)参数不完整或不合法")
            }
        }
    }
}

enum WechslerIQEstimator {
    enum EstimationError: LocalizedError {
        case invalidModel(String), invalidResponses, incomplete, excessiveTimeouts, numericalRange, interruptedSession
        var errorDescription: String? {
            switch self {
            case .invalidModel(let reason): return "暂无法估算 IQ：\(reason)"
            case .invalidResponses: return "作答记录与题库不一致，无法估算 IQ。"
            case .incomplete: return "需完成全部 10 个分测验，且至少有 60 题，才能生成实验性 IQ 估算。"
            case .excessiveTimeouts: return "超过 20% 的项目超时，本次仅报告原始成绩。"
            case .numericalRange: return "模型积分未稳定收敛，本次仅报告原始成绩。"
            case .interruptedSession: return "存在中断项目，本次仅报告已计分题目的成绩，不生成 IQ 估算。"
            }
        }
    }

    /// 均匀随机选项仅为猜测下限假设；自由回忆不使用备选项的猜测率。
    static func probabilities(item: WechslerItem, parameter: WechslerIQModel.ItemParameter,
                              theta: Double) -> [Int: Double] {
        func sigmoid(_ value: Double) -> Double {
            if value >= 0 { return 1 / (1 + exp(-value)) }
            let e = exp(value)
            return e / (1 + e)
        }
        let chanceOfFull = item.requiresRecall ? 0 : Double(item.optionScores.filter { $0 == item.maxScore }.count) / Double(item.options.count)
        if parameter.thresholds.count == 2 {
            let chanceOfAny = Double(item.optionScores.filter { $0 > 0 }.count) / Double(item.options.count)
            let any = chanceOfAny + (1 - chanceOfAny) * sigmoid(parameter.discrimination * (theta - parameter.thresholds[0]))
            let full = chanceOfFull + (1 - chanceOfFull) * sigmoid(parameter.discrimination * (theta - parameter.thresholds[1]))
            return [0: 1 - any, 1: any - full, 2: full]
        }
        let full = chanceOfFull + (1 - chanceOfFull) * sigmoid(parameter.discrimination * (theta - parameter.thresholds[0]))
        return [0: 1 - full, item.maxScore: full]
    }

    /// EAP：N(0,1) 先验，0.025 步长；检查外侧半单位质量，必要时扩展边界。
    /// N(0,1) 是初始模型约定，不是实测人群分布，也不构成 IQ 常模。
    static func posteriorMean(evidence: [(item: WechslerItem, parameter: WechslerIQModel.ItemParameter, score: Int)]) throws -> Double {
        for radius in [6.0, 10.0, 14.0, 18.0] {
            let grid: [Double] = (0...Int(radius * 80)).map { -radius + Double($0) * 0.025 }
            let logs: [Double] = grid.map { theta -> Double in
                var logWeight = -theta * theta / 2
                for row in evidence {
                    let p = probabilities(item: row.item, parameter: row.parameter, theta: theta)[row.score] ?? 0
                    logWeight += log(max(1e-14, p))
                }
                return logWeight
            }
            let peak = logs.max() ?? 0
            let weights = logs.map { exp($0 - peak) }
            let total = weights.reduce(0, +)
            guard total.isFinite, total > 0 else { throw EstimationError.numericalRange }
            let edge = zip(grid, weights).reduce(0.0) { sum, row in
                sum + (abs(row.0) >= radius - 0.5 ? row.1 : 0)
            } / total
            if edge < 1e-8 {
                return zip(grid, weights).reduce(0.0) { $0 + $1.0 * $1.1 } / total
            }
        }
        throw EstimationError.numericalRange
    }

    /// 分测验能力向中心收缩的强度（单位为 θ）。1.5 表示分测验自身的估计占主导，
    /// 中心只提供少量约束，用来抑制 12 题的小样本噪声，又不至于抹掉领域差异。
    static let shrinkageSD = 1.5

    /// 3PL 项目的 Fisher 信息。对部分得分题按嵌套 Rasch 模型处理：
    /// 「至少得 1 分」与「得满分」两层信息相加。
    static func fisherInformation(item: WechslerItem, parameter: WechslerIQModel.ItemParameter,
                                  theta: Double) -> Double {
        func sigmoid(_ value: Double) -> Double {
            if value >= 0 { return 1 / (1 + exp(-value)) }
            let e = exp(value)
            return e / (1 + e)
        }
        let cAny = item.requiresRecall ? 0 : Double(item.optionScores.filter { $0 > 0 }.count) / Double(item.options.count)
        let cFull = item.requiresRecall ? 0 : Double(item.optionScores.filter { $0 == item.maxScore }.count) / Double(item.options.count)
        func information(guessing: Double, threshold: Double) -> Double {
            let slope = sigmoid(parameter.discrimination * (theta - threshold))
            let probability = guessing + (1 - guessing) * slope
            guard probability > 0, probability < 1 else { return 0 }
            // dp/dtheta = a(p - c)(1 - p)
            let derivative = parameter.discrimination * (probability - guessing) * (1 - probability)
            return derivative * derivative / (probability * (1 - probability))
        }
        if parameter.thresholds.count == 2 {
            return information(guessing: cAny, threshold: parameter.thresholds[0])
                + information(guessing: cFull, threshold: parameter.thresholds[1])
        }
        return information(guessing: cFull, threshold: parameter.thresholds[0])
    }

    /// 某个能力水平下，这组项目的预期得分率。
    ///
    /// 用于给出「本题库基准」：θ=0 时的预期得分率反映该分测验在当前题目参数下有多难，
    /// 让使用者能把「这个分测验一贯更难」与「这次表现较差」区分开。
    static func expectedRate(items: [WechslerItem], parameters: [String: WechslerIQModel.ItemParameter],
                             theta: Double) -> Double {
        let maxTotal = items.reduce(0) { $0 + $1.maxScore }
        guard maxTotal > 0 else { return 0 }
        let earned = items.reduce(0.0) { sum, item in
            guard let parameter = parameters[item.id] else { return sum }
            let distribution = probabilities(item: item, parameter: parameter, theta: theta)
            return sum + distribution.reduce(0.0) { $0 + Double($1.key) * $1.value }
        }
        return earned / Double(maxTotal)
    }

    /// 局部标准误：SE = 1 / sqrt(总 Fisher 信息)。信息趋近于零（天花板或地板）时返回无穷大。
    static func standardError(items: [WechslerItem], parameters: [String: WechslerIQModel.ItemParameter],
                              theta: Double) -> Double {
        let information = items.reduce(0.0) { sum, item in
            guard let parameter = parameters[item.id] else { return sum }
            return sum + fisherInformation(item: item, parameter: parameter, theta: theta)
        }
        guard information > 1e-9 else { return .infinity }
        return 1 / sqrt(information)
    }

    /// 分层能力估计：总体能力 + 各分测验能力。
    ///
    /// 分测验先各自独立估计（先验 N(0,1)），再向「各分测验信息加权的中心」做经验贝叶斯收缩。
    /// 中心取自各分测验自身的估计而不是总体能力：总体能力由全部项目聚合而来，
    /// 在后验上比子测验平均更极端，用它作收缩中心会把各领域拉平，抹掉领域差异。
    /// 标准误仍取分测验在自身 θ 处的局部 Fisher 标准误，收缩不使其变小，避免区间虚假收窄。
    static func ability(items: [WechslerItem], responses: [WechslerResponse],
                        model: WechslerIQModel) throws -> WechslerAbility {
        let prepared = try prepare(items: items, responses: responses, model: model)
        let globalTheta = try posteriorMean(evidence: prepared.evidence)
        let parameters = Dictionary(uniqueKeysWithValues: model.items.map { ($0.itemID, $0) })

        var independent: [(subtest: WechslerSubtest, theta: Double, error: Double, baseline: Double, maxTotal: Int)] = []
        for subtest in WechslerSubtest.allCases {
            let subset = prepared.evidence.filter { $0.item.subtest == subtest }
            guard !subset.isEmpty else { continue }
            let theta = try posteriorMean(evidence: subset)
            let error = standardError(items: subset.map(\.item), parameters: parameters, theta: theta)
            let baseline = expectedRate(items: subset.map(\.item), parameters: parameters, theta: 0)
            let maxTotal = subset.reduce(0) { $0 + $1.item.maxScore }
            independent.append((subtest, theta, error, baseline, maxTotal))
        }

        let weights = independent.map { 1 / max($0.error * $0.error, 1e-6) }
        let totalWeight = weights.reduce(0, +)
        var center = 0.0
        for (index, entry) in independent.enumerated() { center += entry.theta * weights[index] }
        center = totalWeight > 0 ? center / totalWeight : globalTheta

        let centerWeight = 1 / (shrinkageSD * shrinkageSD)
        var subtests: [WechslerAbility.SubtestAbility] = []
        for (index, entry) in independent.enumerated() {
            let theta = (weights[index] * entry.theta + centerWeight * center) / (weights[index] + centerWeight)
            subtests.append(.init(subtest: entry.subtest, theta: theta, standardError: entry.error,
                                  baselineRate: entry.baseline))
        }

        let globalError = standardError(items: items, parameters: parameters, theta: globalTheta)
        // 本次实际得分率，以及模型定义的平均能力（θ=0）时题库的预期得分率。
        // 两者并列才能看出分数的来源：偏低的是作答表现还是题库刻度。
        let totalMax = items.reduce(0) { $0 + $1.maxScore }
        let earned = prepared.evidence.reduce(0.0) { $0 + Double($1.score) }
        let overallRate = totalMax > 0 ? earned / Double(totalMax) : 0
        let expectedTotal = independent.reduce(0.0) { $0 + $1.baseline * Double($1.maxTotal) }
        let bankAverageRate = totalMax > 0 ? expectedTotal / Double(totalMax) : 0
        return WechslerAbility(globalTheta: globalTheta, globalStandardError: globalError,
                               centerTheta: center, overallRate: overallRate,
                               bankAverageRate: bankAverageRate, subtests: subtests)
    }

    /// 校验题库、作答与模型的一致性，并整理出计分证据。质量门槛与 `estimate` 相同。
    static func prepare(items: [WechslerItem], responses: [WechslerResponse],
                        model: WechslerIQModel) throws -> (evidence: [(item: WechslerItem, parameter: WechslerIQModel.ItemParameter, score: Int)], timedOut: Int) {
        try WechslerLoader.validate(items)
        try model.validate(for: items)
        guard items.count >= 60, responses.count == items.count else { throw EstimationError.incomplete }
        guard Set(responses.map(\.itemID)).count == responses.count,
              Set(responses.map(\.itemID)) == Set(items.map(\.id)) else { throw EstimationError.invalidResponses }
        let byID = Dictionary(uniqueKeysWithValues: responses.map { ($0.itemID, $0) })
        let parameters = Dictionary(uniqueKeysWithValues: model.items.map { ($0.itemID, $0) })
        for item in items {
            guard let response = byID[item.id], response.subtest == item.subtest,
                  response.maxScore == item.maxScore, item.optionScores.contains(response.score),
                  response.elapsedSeconds.isFinite, (0...Double(item.subtest.timeLimit)).contains(response.elapsedSeconds) else {
                throw EstimationError.invalidResponses
            }
            if response.outcome == .timedOut || response.outcome == .interrupted {
                guard response.score == 0, response.answer == nil else { throw EstimationError.invalidResponses }
            } else if let answer = response.answer {
                if item.requiresRecall {
                    guard item.recallScore(for: answer) == response.score else { throw EstimationError.invalidResponses }
                } else {
                    guard zip(item.options, item.optionScores).contains(where: { $0.0 == answer && $0.1 == response.score }) else {
                        throw EstimationError.invalidResponses
                    }
                }
            } else { throw EstimationError.invalidResponses }
        }
        guard !responses.contains(where: { $0.outcome == .interrupted }) else { throw EstimationError.interruptedSession }
        let timedOut = responses.filter { $0.outcome == .timedOut }.count
        guard Double(timedOut) / Double(items.count) <= 0.2 else { throw EstimationError.excessiveTimeouts }
        let evidence = items.compactMap { item -> (item: WechslerItem, parameter: WechslerIQModel.ItemParameter, score: Int)? in
            guard let parameter = parameters[item.id], let response = byID[item.id] else { return nil }
            return (item, parameter, response.score)
        }
        return (evidence, timedOut)
    }

    static func estimate(items: [WechslerItem], responses: [WechslerResponse],
                         model: WechslerIQModel) throws -> WechslerIQEstimate {
        let prepared = try prepare(items: items, responses: responses, model: model)
        let theta = try posteriorMean(evidence: prepared.evidence)
        var flags: [WechslerIQEstimate.Flag] = []
        if responses.allSatisfy({ $0.score == $0.maxScore }) { flags.append(.ceiling) }
        if responses.allSatisfy({ $0.score == 0 }) { flags.append(.floor) }
        if prepared.timedOut > 0 { flags.append(.timeouts) }
        return WechslerIQEstimate(value: Int((100 + 15 * theta).rounded()), theta: theta,
                                  modelVersion: model.version, bankVersion: model.bankVersion,
                                  calibrationStatus: model.calibrationStatus, ageAdjusted: false,
                                  answeredCount: responses.count - prepared.timedOut,
                                  timedOutCount: prepared.timedOut, flags: flags)
    }
}
