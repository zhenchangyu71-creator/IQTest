import Foundation

/// 自编推理题的经验量尺输出，参数未经样本拟合，不包含人群百分位。
struct RavenIQEstimate: Codable {
    let value: Int
    let modelVersion: String
    let bankVersion: String
    let ageAdjusted: Bool
    let calibrationStatus: String
    /// 95% 估计区间的上下界。旧记录没有该字段时为 nil。
    let confidenceLower: Int?
    let confidenceUpper: Int?

    static let currentModelVersion = "raven-heuristic-v2"
    static let currentBankVersion = "raven-practice-2026-10-22-v3"
    static let notice = "实验性 IQ 估算尚未经过人群常模或正式测验对照验证；未按年龄校准，误差范围未知。"
    /// 经验换算中「得分率上一个标准差」对应的 IQ 分量。
    static let scoreRateSD = 0.20
    /// 估算值的可解释上下限。
    static let valueRange = 55...145

    static func make(score: Int, total: Int, difficulty: Difficulty) -> Self? {
        guard total > 0, (0...total).contains(score) else { return nil }
        // 保留已有难度下的经验映射，去掉没有年龄常模依据的人工加分。
        let rate = Double(score) / Double(total)
        // 12 题的小样本使观测比例本身带有很大抽样误差，区间按 Wilson 得分区间换算。
        let bounds = IQScale.wilsonInterval(successes: score, trials: total)
        return Self(value: toIQ(rate, difficulty: difficulty),
                    modelVersion: currentModelVersion, bankVersion: currentBankVersion,
                    ageAdjusted: false, calibrationStatus: "heuristic",
                    confidenceLower: toIQ(bounds.lower, difficulty: difficulty),
                    confidenceUpper: toIQ(bounds.upper, difficulty: difficulty))
    }

    /// 得分率 → IQ 量尺，区间端点沿用与点估计相同的经验映射。
    private static func toIQ(_ rate: Double, difficulty: Difficulty) -> Int {
        let offset: Double = (rate - difficulty.scoreMean) / scoreRateSD * 15.0
        let raw: Double = IQScale.compositeMean + offset
        let rounded = Int(raw.rounded())
        return min(valueRange.upperBound, max(valueRange.lowerBound, rounded))
    }
}
