import Foundation

/// 韦氏风格的量表分剖面：尺度分 → 指数分 → 全量表分。
///
/// 换算结构参照韦氏标准十分法（尺度分 Mean 10 / SD 3、指数分与全量表分 Mean 100 / SD 15），
/// 指数分与全量表分对「尺度分之和」的线性关系来自 Pearson 官方示例报告的反推值，
/// 而不是逐龄的官方换算表——本应用没有人群常模，也没有使用任何韦氏原始分换算表。
///
/// 因此剖面描述的是本练习题库上的相对表现，不能解释为同龄人排名或正式韦氏 IQ。
struct WechslerProfile: Codable {
    enum CalibrationStatus: String, Codable { case uncalibrated }

    /// 分测验尺度分。
    struct ScaledScore: Codable, Identifiable {
        var id: String { subtest.rawValue }
        let subtest: WechslerSubtest
        /// 尺度分，1...19。
        let scaled: Int
        /// 标准九分，1...9。
        let standardNine: Int
        let percentile: Double
        let band: IQScale.ScaledBand
        /// 该分测验尺度分的估计标准误（尺度分单位）。12 题的小样本使这一项通常有 3–7 分，
        /// 能力很高、天花板附近时更宽。
        let standardError: Double?
        /// 95% 估计区间的上下界，已限制在 1...19。
        let confidenceLower: Int?
        let confidenceUpper: Int?
        /// 该分测验在 θ=0 时的预期得分率，即本题库里的难度基准。
        /// 旧记录没有该字段时为 nil。
        let baselineRate: Double?
    }

    /// 领域指数分（合成分）。
    struct IndexScore: Codable, Identifiable {
        var id: String { domain.rawValue }
        let domain: WechslerDomain
        let score: Int
        let percentile: Double
        let band: IQScale.CompositeBand
        let standardError: Double
        let confidenceLower: Int?
        let confidenceUpper: Int?
    }

    /// 全量表分（FSIQ）。
    struct FullScaleScore: Codable {
        let score: Int
        let percentile: Double
        let band: IQScale.CompositeBand
        let standardError: Double
        let confidenceLower: Int?
        let confidenceUpper: Int?
    }

    /// 两个领域指数分之间的比较。
    ///
    /// 两个领域由互不相交的题目构成，其指数分的估计误差可以视为独立，
    /// 因此差异的联合标准误可直接相减求平方和开根。
    struct DomainComparison: Codable, Identifiable {
        var id: String { first.rawValue + "-" + second.rawValue }
        let first: WechslerDomain
        let second: WechslerDomain
        /// 第一个领域减去第二个领域。
        let difference: Int
        /// 差异的联合标准误。
        let standardError: Double
        /// 差异是否达到 95% 置信水平。
        let significant: Bool
    }

    let fullScale: FullScaleScore
    let indices: [IndexScore]
    let subtests: [ScaledScore]
    /// 领域两两比较。旧记录没有该字段时为 nil。
    let domainComparisons: [DomainComparison]?
    /// 本次作答的实际得分率。旧记录没有该字段时为 nil。
    let overallRate: Double?
    /// 模型定义的平均能力（θ=0）时题库整体的预期得分率。旧记录没有该字段时为 nil。
    let bankAverageRate: Double?
    let flags: [WechslerIQEstimate.Flag]
    /// 估计区间无法给出：Fisher 信息趋零、区间宽到失去解释力，
    /// 或分数被量表边界截断导致区间退化。
    let intervalUnavailable: Bool
    let modelVersion: String
    let bankVersion: String
    /// 换算标定版本。斜率一旦用真实样本重新标定，取值随之改变，
    /// 历史记录据此可以区分不同标定下的分数。旧记录没有该字段时为 nil。
    let scoringVersion: String?
    let calibrationStatus: CalibrationStatus
}

/// 把分层能力估计换算成韦氏风格的量表分剖面。
enum WechslerProfileScorer {
    /// 指数分对「两个分测验尺度分之和」的斜率。
    /// 由 Pearson 官方示例报告反推，五个指数的拟合误差均不超过 1.5 分。
    static let indexSlope = 2.75
    /// 十个核心分测验尺度分之和 → 全量表分的斜率（韦氏 WAIS-IV 的分测验结构）。
    static let fullScaleSlope = 0.72
    /// 七个主分测验尺度分之和 → 全量表分的斜率（韦氏 WAIS-5 / WISC-V 的分测验结构）。
    static let fullScaleSlopeSevenSubtests = 0.96
    /// 指数分的估计标准误下限，取韦氏手册实测的 95% 区间半宽 ±7 分。
    static let indexSEMFloor = 7.0 / 1.96
    /// 全量表分的估计标准误下限，取韦氏手册实测的 95% 区间半宽 ±5 分。
    static let fullScaleSEMFloor = 5.0 / 1.96
    /// 合成分的取值上下限，与韦氏报告的可解释范围一致。
    static let compositeRange = 50...145
    /// 95% 区间半宽超过该值时，区间宽到失去解释力，不再作为有效区间展示。
    static let maximumIntervalHalfWidth = 30.0

    /// 尺度分之和 → 合成分。
    ///
    /// 斜率由调用方传入：领域指数分统一用 `indexSlope`，全量表分按分测验个数
    /// 在 0.96 与 0.72 之间选。这些斜率是为韦氏题库借用的，在本项目的题目参数下
    /// 并不能让合成分的标准差落在 15 上——实际离散度与两个施测口径的差别，
    /// 见 docs/WECHSLER_STYLE_SCORING.md 的「标定状态与已知偏差」。
    static func composite(scaledSum: Int, subtestCount: Int, slope: Double) -> Int {
        let raw = IQScale.compositeMean + slope * (Double(scaledSum) - IQScale.scaledMean * Double(subtestCount))
        return min(compositeRange.upperBound, max(compositeRange.lowerBound, Int(raw.rounded())))
    }

    /// 分测验尺度分之和 → 全量表分。七个分测验用 WAIS-5/WISC-V 的斜率，更多分测验用 WAIS-IV 的斜率。
    static func fullScale(scaledSum: Int, subtestCount: Int) -> Int {
        let slope = subtestCount <= 7 ? fullScaleSlopeSevenSubtests : fullScaleSlope
        return composite(scaledSum: scaledSum, subtestCount: subtestCount, slope: slope)
    }

    /// 当前换算标定版本。斜率借用自韦氏官方示例报告，尚未用本项目数据重新标定，
    /// 详见 docs/WECHSLER_STYLE_SCORING.md 的「标定状态与已知偏差」。
    static let currentScoringVersion = "wechsler-style-borrowed-v1"

    static func make(ability: WechslerAbility, flags: [WechslerIQEstimate.Flag],
                     modelVersion: String, bankVersion: String) -> WechslerProfile {
        let scaledScores = ability.subtests.map { entry -> WechslerProfile.ScaledScore in
            let scaled = min(IQScale.scaledRange.upperBound,
                             max(IQScale.scaledRange.lowerBound,
                                 Int((IQScale.scaledMean + IQScale.scaledSD * entry.theta).rounded())))
            // 尺度分的标准误 = 3（尺度分标准差）× θ 的标准误。
            let scaledError = IQScale.scaledSD * entry.standardError
            let lower = min(IQScale.scaledRange.upperBound,
                            max(IQScale.scaledRange.lowerBound,
                                Int((Double(scaled) - 1.96 * scaledError).rounded())))
            let upper = min(IQScale.scaledRange.upperBound,
                            max(IQScale.scaledRange.lowerBound,
                                Int((Double(scaled) + 1.96 * scaledError).rounded())))
            return .init(subtest: entry.subtest, scaled: scaled,
                         standardNine: IQScale.standardNine(fromScaled: scaled),
                         percentile: IQScale.percentile(fromScaled: Double(scaled)),
                         band: IQScale.ScaledBand.band(for: scaled),
                         standardError: scaledError,
                         confidenceLower: lower, confidenceUpper: upper,
                         baselineRate: entry.baselineRate)
        }

        var indices: [WechslerProfile.IndexScore] = []
        for domain in WechslerDomain.allCases {
            let members = scaledScores.filter { $0.subtest.domain == domain }
            guard !members.isEmpty else { continue }
            let errors = ability.subtests.filter { $0.subtest.domain == domain }.map(\.standardError)
            let propagated = indexSlope * errors.reduce(0) { $0 + $1 * $1 }.squareRoot()
            let standardError = max(propagated, indexSEMFloor)
            let score = composite(scaledSum: members.reduce(0) { $0 + $1.scaled },
                                  subtestCount: members.count, slope: indexSlope)
            let bounds = confidenceBounds(score: score, standardError: standardError)
            indices.append(.init(domain: domain, score: score,
                                 percentile: IQScale.percentile(fromComposite: Double(score)),
                                 band: IQScale.CompositeBand.band(for: Double(score)),
                                 standardError: standardError,
                                 confidenceLower: bounds.lower, confidenceUpper: bounds.upper))
        }

        let scaledSum = scaledScores.reduce(0) { $0 + $1.scaled }
        let fullScaleSlopeUsed = scaledScores.count <= 7 ? fullScaleSlopeSevenSubtests : fullScaleSlope
        let propagatedFull = fullScaleSlopeUsed * ability.subtests.reduce(0.0) { $0 + $1.standardError * $1.standardError }.squareRoot()
        let fullScaleSEM = max(propagatedFull, fullScaleSEMFloor)
        let fullScaleValue = fullScale(scaledSum: scaledSum, subtestCount: scaledScores.count)
        let fullScaleBounds = confidenceBounds(score: fullScaleValue, standardError: fullScaleSEM)
        let fullScaleScore = WechslerProfile.FullScaleScore(
            score: fullScaleValue,
            percentile: IQScale.percentile(fromComposite: Double(fullScaleValue)),
            band: IQScale.CompositeBand.band(for: Double(fullScaleValue)),
            standardError: fullScaleSEM,
            confidenceLower: fullScaleBounds.lower, confidenceUpper: fullScaleBounds.upper)

        let comparisons = domainComparisons(indices: indices)

        let intervalUnavailable = !fullScaleSEM.isFinite || indices.contains { !$0.standardError.isFinite }
            || 1.96 * fullScaleSEM > maximumIntervalHalfWidth
            || indices.contains { 1.96 * $0.standardError > maximumIntervalHalfWidth }
            || fullScaleBounds.lower == nil || indices.contains { $0.confidenceLower == nil }
        return WechslerProfile(fullScale: fullScaleScore, indices: indices, subtests: scaledScores,
                               domainComparisons: comparisons,
                               overallRate: ability.overallRate,
                               bankAverageRate: ability.bankAverageRate,
                               flags: flags,
                               intervalUnavailable: intervalUnavailable,
                               modelVersion: modelVersion, bankVersion: bankVersion,
                               scoringVersion: currentScoringVersion,
                               calibrationStatus: .uncalibrated)
    }

    /// 领域两两比较。两个领域的题目互不相交，估计误差可视为独立，
    /// 差异的标准误为两者标准误的平方和开根；差异超过 1.96 倍标准误才算达到 95% 置信水平。
    private static func domainComparisons(indices: [WechslerProfile.IndexScore]) -> [WechslerProfile.DomainComparison] {
        var result: [WechslerProfile.DomainComparison] = []
        for first in 0..<indices.count {
            for second in (first + 1)..<indices.count {
                let a = indices[first], b = indices[second]
                let standardError = (a.standardError * a.standardError + b.standardError * b.standardError).squareRoot()
                let difference = a.score - b.score
                result.append(.init(first: a.domain, second: b.domain, difference: difference,
                                    standardError: standardError,
                                    significant: standardError.isFinite
                                        && abs(Double(difference)) > 1.96 * standardError))
            }
        }
        return result
    }

    /// 95% 置信区间。标准误无穷大（信息趋零）时不给出区间；
    /// 区间上下界限制在合成分的可解释范围内。
    ///
    /// 分数被量表边界截断时区间会塌成零宽（如 145–145），读起来像估计极其精确，
    /// 实际上只是能力估计超出了量表可解释范围。这种情况下整段区间标为不可估计。
    private static func confidenceBounds(score: Int, standardError: Double) -> (lower: Int?, upper: Int?) {
        guard standardError.isFinite else { return (nil, nil) }
        let halfWidth = 1.96 * standardError
        let lower = min(compositeRange.upperBound,
                        max(compositeRange.lowerBound, Int((Double(score) - halfWidth).rounded())))
        let upper = min(compositeRange.upperBound,
                        max(compositeRange.lowerBound, Int((Double(score) + halfWidth).rounded())))
        if lower == score || upper == score { return (nil, nil) }
        return (lower, upper)
    }
}
