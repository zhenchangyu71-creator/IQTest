import Foundation

/// 分层能力估计结果：一次作答同时给出总体能力与各分测验的能力。
///
/// 总体能力用全部项目的后验均值。分测验各自独立估计，再向信息加权的中心做经验贝叶斯收缩，
/// 抑制 12 题小样本的噪声，同时保留领域之间的差异。标准误来自局部 Fisher 信息，
/// 不受收缩压缩影响，因此不会因为数据稀少而虚假地收窄。
struct WechslerAbility: Codable {
    struct SubtestAbility: Codable {
        let subtest: WechslerSubtest
        /// 该分测验的能力参数，单位为 θ（模型标准差）。
        let theta: Double
        /// 由该分测验项目在 θ 处的 Fisher 信息换算的局部标准误。
        let standardError: Double
        /// 该分测验在 θ=0 时的预期得分率，即本题库里的难度基准。
        /// 数值越低说明该分测验在当前题目参数下一贯更难。
        let baselineRate: Double
    }

    let globalTheta: Double
    let globalStandardError: Double
    /// 各分测验信息加权的中心，收缩时作为目标。
    let centerTheta: Double
    /// 本次作答的实际得分率。
    let overallRate: Double
    /// 模型定义的平均能力（θ=0）时，题库整体的预期得分率。
    /// 与实际得分率并列，才能看出分数偏低是作答表现还是题库刻度造成的。
    let bankAverageRate: Double
    let subtests: [SubtestAbility]

    func ability(for subtest: WechslerSubtest) -> SubtestAbility? {
        subtests.first { $0.subtest == subtest }
    }
}
