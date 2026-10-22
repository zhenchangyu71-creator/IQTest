import SwiftUI

/// 分测验最佳练习得分率雷达图（自绘，兼容 iOS 17）
/// scores 与 WechslerSubtest.allCases 一一对应，nil 表示该分测验尚未练习，0 是实际零分
struct PracticeRadarView: View {
    /// 主序列（如本次测验 / 练习最佳），与 WechslerSubtest.allCases 一一对应，nil 表示无数据
    let scores: [Int?]
    /// 可选对比序列（如练习最佳），样式为橙色虚线
    var comparison: [Int?]? = nil
    /// 是否显示底部统计文案（结果页自带图例时关闭）
    var showCaption: Bool = true
    /// 各分测验的难度基准（本题库在模型平均能力下的预期得分率），与 WechslerSubtest.allCases 一一对应，
    /// nil 表示该分测验没有基准数据。给出后按基准归一：外圈表示「达到该分测验的本题库平均水平」，各轴才可横向比较。
    var baselines: [Double?]? = nil

    private let labels: [String] = WechslerSubtest.allCases.map(\.rawValue)
    private let maxScore: CGFloat = 100
    private let axisCount: Int = WechslerSubtest.allCases.count

    private var practicedCount: Int { scores.compactMap { $0 }.count }
    private var isNormalized: Bool { baselines != nil }

    /// 图上用于定位的数值。归一模式下为「达到基准的百分比」，超过基准记为满格。
    private func displayValue(_ value: Int?, at index: Int) -> CGFloat {
        guard let value else { return 0 }
        guard let baselines, index < baselines.count, let baseline = baselines[index], baseline > 0 else {
            return CGFloat(value)
        }
        return min(100, CGFloat(Double(value) / baseline * 100))
    }

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                let radius = side / 2 - 40 // 外圈留给文字标签
                ZStack {
                    grid(center: center, radius: radius)
                    if let comparison {
                        seriesPolygon(center: center, radius: radius, values: comparison,
                                      color: .orange, filled: false, dotRadius: 3)
                    }
                    seriesPolygon(center: center, radius: radius, values: scores,
                                  color: .purple, filled: true, dotRadius: 4)
                    ForEach(Array(labels.enumerated()), id: \.offset) { index, text in
                        label(index: index, text: text, center: center, radius: radius)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 360, maxHeight: 300)
            .frame(maxWidth: .infinity)

            if showCaption {
                if practicedCount == 0 {
                    Text("完成任意分测验练习后，这里会生成题目得分率雷达图")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if isNormalized {
                    Text("各轴为达到该分测验本题库平均水平的程度；超过基准记为满格。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    let practiced = scores.compactMap { $0 }
                    let avg = Double(practiced.reduce(0, +)) / Double(practiced.count)
                    Text("已练 \(practicedCount)/10 个分测验 · 平均 \(String(format: "%.1f", avg))%（练习得分率）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - 角度与坐标

    private func angle(_ index: Int) -> CGFloat {
        -CGFloat.pi / 2 + CGFloat(index) * 2 * .pi / CGFloat(axisCount)
    }

    private func point(center: CGPoint, radius: CGFloat, index: Int) -> CGPoint {
        CGPoint(
            x: center.x + radius * cos(angle(index)),
            y: center.y + radius * sin(angle(index))
        )
    }

    // MARK: - 网格

    private func grid(center: CGPoint, radius: CGFloat) -> some View {
        Canvas { context, _ in
            // 同心环：25%、50%、75%、100%
            for fraction in [0.25, 0.5, 0.75, 1.0] {
                var path = Path()
                for i in 0..<axisCount {
                    let p = point(center: center, radius: radius * fraction, index: i)
                    if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
                }
                path.closeSubpath()
                context.stroke(
                    path,
                    with: .color(Color.secondary.opacity(fraction == 1.0 ? 0.4 : 0.15)),
                    lineWidth: 1
                )
            }
            // 轴线
            for i in 0..<axisCount {
                let p = point(center: center, radius: radius, index: i)
                var path = Path()
                path.move(to: center)
                path.addLine(to: p)
                context.stroke(path, with: .color(Color.secondary.opacity(0.15)), lineWidth: 1)
            }
        }
    }

    // MARK: - 数据多边形

    private func seriesPolygon(center: CGPoint, radius: CGFloat, values: [Int?],
                               color: Color, filled: Bool, dotRadius: CGFloat) -> some View {
        Canvas { context, _ in
            guard values.contains(where: { $0 != nil }) else { return }
            var path = Path()
            for i in 0..<values.count {
                // 有数据的分测验按得分定位；无数据的缩到中心，不参与已练次数统计
                let fraction = displayValue(values[i], at: i) / maxScore
                let p = point(center: center, radius: radius * fraction, index: i)
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            path.closeSubpath()
            if filled {
                context.fill(path, with: .color(color.opacity(0.25)))
                context.stroke(path, with: .color(color), lineWidth: 2)
            } else {
                context.stroke(path, with: .color(color),
                               style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            }

            // 顶点圆点（仅有数据的分测验）
            for i in 0..<values.count where values[i] != nil {
                let fraction = displayValue(values[i], at: i) / maxScore
                let p = point(center: center, radius: radius * fraction, index: i)
                let dot = Path(ellipseIn: CGRect(x: p.x - dotRadius, y: p.y - dotRadius,
                                                 width: dotRadius * 2, height: dotRadius * 2))
                context.fill(dot, with: .color(color))
            }
        }
    }

    // MARK: - 轴标签

    private func label(index: Int, text: String, center: CGPoint, radius: CGFloat) -> some View {
        let p = CGPoint(
            x: center.x + (radius + 22) * cos(angle(index)),
            y: center.y + (radius + 22) * sin(angle(index))
        )
        return Text(text)
            .font(.caption2)
            .foregroundStyle(scores[index] != nil ? Color.primary : Color.secondary)
            .lineLimit(1)
            .position(p)
    }
}
