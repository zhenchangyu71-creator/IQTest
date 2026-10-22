import SwiftUI

struct ResultView: View {
    @EnvironmentObject private var viewModel: QuizViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                RecordSaveStatusView(error: viewModel.saveError, retry: viewModel.retrySave)
                VStack(spacing: 8) {
                    Text(viewModel.endedEarly ? "本次练习提前结束" : "本次推理练习报告").font(.headline)
                    if let estimate = viewModel.ravenEstimate {
                        Text("实验性 IQ 估算").font(.subheadline)
                        Text("\(estimate.value)")
                            .font(.system(size: 72, weight: .bold, design: .rounded)).foregroundStyle(.purple)
                            .accessibilityIdentifier("experimentalRavenIQValue")
                        Text("未校准 · 年龄仅作记录、未参与换算").font(.headline).foregroundStyle(.secondary)
                        if let lower = estimate.confidenceLower, let upper = estimate.confidenceUpper {
                            Text("95% 估计区间 \(lower)–\(upper)")
                                .font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                        }
                        let percentile = IQScale.percentile(fromComposite: Double(estimate.value))
                        Text("\(IQScale.CompositeBand.band(for: Double(estimate.value)).rawValue) · 近似百分位 ≈ \(Int(percentile.rounded()))")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Text("每轮只有 12 题，区间通常很宽；点估计不要当作精确测量。")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("未完成 · 不生成 IQ 估算").font(.headline)
                    }
                    Text("原始分 \(viewModel.score)/\(viewModel.scoredItemCount) · 已记录 \(viewModel.scoredItemCount)/\(viewModel.questions.count) 题")
                        .font(.subheadline)
                    Text("\(viewModel.sessionAge) 岁 · \(viewModel.sessionDifficulty.rawValue) · 每题 \(viewModel.sessionDifficulty.secondsPerQuestion) 秒")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(RavenIQEstimate.notice).font(.footnote).foregroundStyle(.secondary)
                    if viewModel.endedEarly {
                        Text("已提交及已超时的项目已保存；未提交项目未计分。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .multilineTextAlignment(.center).padding(.top, 20)

                VStack(alignment: .leading, spacing: 12) {
                    Text("各类题目表现").font(.headline)
                    ForEach(viewModel.categoryBreakdown.filter { $0.total > 0 }, id: \.category) { item in
                        HStack {
                            Text(item.category.rawValue)
                            Spacer()
                            Text("\(item.correct)/\(item.total)").monospacedDigit()
                        }
                    }
                    Text("不同题型的原始得分不等同于标准化能力指数。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding().background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))

                RecordedItemsView(items: viewModel.reviewItems)
                if let record = viewModel.completedRecord { RecordExportButton(records: [record]) }
                ResultExitActions(hasUnsavedRecord: viewModel.saveError != nil,
                                  again: viewModel.start, home: viewModel.reset)
                Text("题库 \(RavenIQEstimate.currentBankVersion) · 模型 \(RavenIQEstimate.currentModelVersion)")
                    .font(.caption2).foregroundStyle(.secondary).padding(.bottom, 20)
            }
            .padding(.horizontal, 24)
        }
    }
}
