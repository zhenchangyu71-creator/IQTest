import SwiftUI

/// 韦氏风格结果报告：FSIQ + 四指数 + 分量表量表分
struct WechslerResultView: View {
    @EnvironmentObject private var vm: WechslerViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // FSIQ
                VStack(spacing: 8) {
                    Text("全量表智商")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("\(vm.fsiq)")
                        .font(.system(size: 84, weight: .bold, design: .rounded))
                        .foregroundStyle(.purple)
                    Text("超过全球约 \(vm.percentileValue)% 的人")
                        .font(.headline)
                    Text("按 \(AgeBand.current.title) 年龄常模校准（简化）")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, 20)

                // 四大指数
                VStack(alignment: .leading, spacing: 12) {
                    Text("指数分数")
                        .font(.headline)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(vm.indexScores, id: \.domain) { item in
                            VStack(spacing: 4) {
                                Text("\(item.score)")
                                    .font(.title2.bold())
                                    .foregroundStyle(.purple)
                                Text(item.domain.rawValue)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground).opacity(0.5), in: RoundedRectangle(cornerRadius: 16))

                // 分量表雷达图：本次测验 vs 练习最佳
                VStack(alignment: .leading, spacing: 12) {
                    Text("分量表雷达图")
                        .font(.headline)
                    PracticeRadarView(
                        scores: WechslerSubtest.allCases.map { sub in
                            vm.results.first(where: { $0.subtest == sub })?.scaled ?? 0
                        },
                        comparison: WechslerSubtest.allCases.map { PracticeStore.best(subtest: $0) },
                        showCaption: false
                    )
                    HStack(spacing: 16) {
                        Label("本次测验", systemImage: "circle.fill")
                            .foregroundStyle(.purple)
                        Label("练习最佳", systemImage: "circle.fill")
                            .foregroundStyle(.orange)
                        Spacer()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground).opacity(0.5), in: RoundedRectangle(cornerRadius: 16))

                // 分量表量表分
                VStack(alignment: .leading, spacing: 12) {
                    Text("分测验量表分")
                        .font(.headline)
                    ForEach(vm.results, id: \.subtest) { result in
                        HStack(spacing: 12) {
                            Text(result.subtest.rawValue)
                                .font(.subheadline)
                                .frame(width: 80, alignment: .leading)
                            ProgressView(value: Double(result.scaled), total: 19.0)
                                .tint(result.scaled >= 13 ? .green : (result.scaled >= 8 ? .purple : .orange))
                            Text("\(result.scaled)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 24, alignment: .trailing)
                        }
                    }
                    Text("量表分均值 10 分、标准差 3 分；指数与 FSIQ 均值 100、标准差 15（简化常模，仅供娱乐参考）。")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground).opacity(0.5), in: RoundedRectangle(cornerRadius: 16))

                // 操作按钮
                VStack(spacing: 12) {
                    Button {
                        vm.start()
                    } label: {
                        Text("再测一次")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)

                    Button("返回首页") {
                        vm.reset()
                    }
                    .foregroundStyle(.secondary)
                }

                Text("本测试参照韦氏量表施测流程简化制作，不等同于专业心理测评。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 20)
            }
            .padding(.horizontal, 24)
        }
    }
}
