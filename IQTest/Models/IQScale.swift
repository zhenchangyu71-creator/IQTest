import Foundation

/// 韦氏量表的正态量尺与描述等级。
///
/// 常数取自韦氏标准十分法（standard score）：尺度分 Mean 10 / SD 3、取值 1...19；
/// 指数分与全量表分 Mean 100 / SD 15。这些是量表分本身的定义，不是本应用题库的人群常模。
enum IQScale {
    static let scaledMean = 10.0
    static let scaledSD = 3.0
    static let scaledRange = 1...19
    static let compositeMean = 100.0
    static let compositeSD = 15.0

    // MARK: - 描述等级

    /// 合成分（指数分 / 全量表分）的经典韦氏七档描述。
    enum CompositeBand: String, Codable, CaseIterable {
        case verySuperior = "极高"
        case superior = "高"
        case highAverage = "中高"
        case average = "平均"
        case lowAverage = "中低"
        case borderline = "临界"
        case extremelyLow = "极低"

        var english: String {
            switch self {
            case .verySuperior: return "Very Superior"
            case .superior: return "Superior"
            case .highAverage: return "High Average"
            case .average: return "Average"
            case .lowAverage: return "Low Average"
            case .borderline: return "Borderline"
            case .extremelyLow: return "Extremely Low"
            }
        }

        /// 分档边界依据韦氏官方描述区间（130 / 120 / 110 / 90 / 80 / 70）。
        static func band(for score: Double) -> CompositeBand {
            switch score {
            case 130...: return .verySuperior
            case 120..<130: return .superior
            case 110..<120: return .highAverage
            case 90..<110: return .average
            case 80..<90: return .lowAverage
            case 70..<80: return .borderline
            default: return .extremelyLow
            }
        }
    }

    /// 尺度分的五档描述，与韦氏报告对尺度分的定性用语一致。
    enum ScaledBand: String, Codable, CaseIterable {
        case veryLow = "很低"
        case belowAverage = "较低"
        case average = "平均"
        case aboveAverage = "较高"
        case veryHigh = "很高"

        var english: String {
            switch self {
            case .veryLow: return "Very Low"
            case .belowAverage: return "Below Average"
            case .average: return "Average"
            case .aboveAverage: return "Above Average"
            case .veryHigh: return "Very High"
            }
        }

        static func band(for scaled: Int) -> ScaledBand {
            switch scaled {
            case ...7: return .veryLow
            case 8...9: return .belowAverage
            case 10...11: return .average
            case 12...13: return .aboveAverage
            default: return .veryHigh
            }
        }
    }

    // MARK: - 正态分布

    /// 标准正态累积分布，误差小于 1.5e-7（Abramowitz & Stegun 7.1.26 的 erf 变体）。
    /// 换算关系为 Φ(z) = 0.5 × (1 + erf(z / √2))。
    static func normalCDF(_ z: Double) -> Double {
        guard z.isFinite else { return z.isNaN ? .nan : (z > 0 ? 1 : 0) }
        let sign = z < 0 ? -1.0 : 1.0
        let x = abs(z) * 0.7071067811865476
        let t = 1.0 / (1.0 + 0.3275911 * x)
        let polynomial = (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t
        return 0.5 * (1.0 + sign * (1.0 - polynomial * exp(-x * x)))
    }

    /// 标准正态分位数，Acklam 有理逼近并做一步 Halley 修正，误差约 1e-13。
    static func inverseNormalCDF(_ p: Double) -> Double {
        guard p > 0, p < 1 else {
            if p <= 0 { return -.infinity }
            if p >= 1 { return .infinity }
            return .nan
        }
        let a = [-39.6968302866538, 220.946098424521, -275.928510446969,
                 138.357751867269, -30.6647980661472, 2.50662827745924]
        let b = [-54.4760987982241, 161.585836858041, -155.698979859887,
                 66.8013118877197, -13.2806815528857]
        let c = [-0.00778489400243029, -0.322396458041136, -2.40075827716184,
                 -2.54973253934373, 4.37466414146497, 2.93816398269878]
        let d = [0.00778469570904146, 0.32246712907004, 2.445134137143, 3.75440866190742]
        let lowerTail = 0.02425
        var z: Double
        if p < lowerTail {
            let q = sqrt(-2 * log(p))
            z = (((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5])
                / ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1)
        } else if p <= 1 - lowerTail {
            let q = p - 0.5
            let r = q * q
            z = (((((a[0] * r + a[1]) * r + a[2]) * r + a[3]) * r + a[4]) * r + a[5]) * q
                / (((((b[0] * r + b[1]) * r + b[2]) * r + b[3]) * r + b[4]) * r + 1)
        } else {
            let q = sqrt(-2 * log(1 - p))
            z = -(((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5])
                / ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1)
        }
        // 一步 Halley 修正，把逼近误差压到双精度极限。
        // 残差必须用精确的 erf 算：若改用上面那个近似 CDF，尾部的密度极小，
        // 残差里的误差会被除以密度放大两个数量级（z 误差可达 2e-4）。
        let error = 0.5 * (1.0 + erf(z * 0.7071067811865476)) - p
        let density = exp(-0.5 * z * z) / sqrt(2 * Double.pi)
        guard density > 0 else { return z }
        let u = error / density
        return z - u / (1 + 0.5 * z * u)
    }

    // MARK: - 百分位换算

    /// 合成分（Mean 100 / SD 15）对应的百分位。
    static func percentile(fromComposite score: Double) -> Double {
        100 * normalCDF((score - compositeMean) / compositeSD)
    }

    /// 尺度分（Mean 10 / SD 3）对应的百分位。
    static func percentile(fromScaled scaled: Double) -> Double {
        100 * normalCDF((scaled - scaledMean) / scaledSD)
    }

    /// 百分位对应的合成分。百分位先夹到 0…100；
    /// 端点 0 与 100 对应 ±∞——正态分布的尾巴无限延伸，这是定义使然，不是缺陷。
    static func composite(fromPercentile percentile: Double) -> Double {
        compositeMean + compositeSD * inverseNormalCDF(min(max(percentile, 0), 100) / 100)
    }

    /// 尺度分降维为标准九分（stanine），切点为 ±0.25 / ±0.75 / ±1.25 / ±1.75。
    ///
    /// 切点定义在标准正态的 z 值上，因此先把尺度分换算成 z 再分档，
    /// 不直接手写整数边界——手写边界容易整体错位一档，把低分段显示得偏高。
    static func standardNine(fromScaled scaled: Int) -> Int {
        let z = (Double(scaled) - scaledMean) / scaledSD
        switch z {
        case ..<(-1.75): return 1
        case ..<(-1.25): return 2
        case ..<(-0.75): return 3
        case ..<(-0.25): return 4
        case ..<0.25: return 5
        case ..<0.75: return 6
        case ..<1.25: return 7
        case ..<1.75: return 8
        default: return 9
        }
    }

    /// 二项比例的 Wilson 得分区间。
    ///
    /// n 次试验中成功 k 次时给出真实比例的区间。相比正态近似，Wilson 区间在比例接近
    /// 0 或 1 时仍然有效——12 题的小样本正是最容易落到极端比例的情形。
    static func wilsonInterval(successes: Int, trials: Int, z: Double = 1.96) -> (lower: Double, upper: Double) {
        guard trials > 0 else { return (0, 1) }
        let n = Double(trials)
        let phat = Double(successes) / n
        let denominator = 1 + z * z / n
        let center = (phat + z * z / (2 * n)) / denominator
        let halfWidth = z * (phat * (1 - phat) / n + z * z / (4 * n * n)).squareRoot() / denominator
        return (max(0, center - halfWidth), min(1, center + halfWidth))
    }
}
