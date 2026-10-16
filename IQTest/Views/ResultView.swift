import SwiftUI

struct ResultView: View {
    @EnvironmentObject private var viewModel: QuizViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // IQ 大数字
                VStack(spacing: 8) {
                    Text("你的估算 IQ")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("\(viewModel.estimatedIQ)")
                        .font(.system(size: 84, weight: .bold, design: .rounded))
                        .foregroundStyle(.purple)
                    HStack(spacing: 8) {
                        Image(systemName: viewModel.difficulty.icon)
                        Text("\(viewModel.testType.shortName) · \(viewModel.difficulty.rawValue) · \(viewModel.questions.count) 题 · \(viewModel.secondsPerQuestion)s/题")
                    }
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.purple, in: Capsule())
                    Text("超过全球约 \(viewModel.percentile)% 的人")
                        .font(.headline)
                    Text("常模：\(AgeBand.current.title)（简化年龄校准）")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(viewModel.iqComment)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 20)

                // 成绩概览
                HStack(spacing: 24) {
                    VStack {
                        Text("\(viewModel.score)/\(viewModel.questions.count)")
                            .font(.title2.bold())
                        Text("答对题目")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Divider().frame(height: 40)
                    VStack {
                        Text("\(viewModel.percentile)%")
                            .font(.title2.bold())
                        Text("百分位")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // 分类维度
                VStack(alignment: .leading, spacing: 12) {
                    Text("维度分析")
                        .font(.headline)
                    ForEach(viewModel.categoryBreakdown, id: \.category) { item in
                        HStack(spacing: 12) {
                            Image(systemName: item.category.systemImage)
                                .frame(width: 24)
                            Text(item.category.rawValue)
                                .frame(width: 70, alignment: .leading)
                            ProgressView(value: Double(item.correct), total: Double(max(item.total, 1)))
                                .tint(item.correct == item.total ? .green : .purple)
                            Text("\(item.correct)/\(item.total)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))

                // 答案回顾
                VStack(alignment: .leading, spacing: 12) {
                    Text("答案回顾")
                        .font(.headline)
                    ForEach(Array(viewModel.questions.enumerated()), id: \.element.id) { index, question in
                        let userAnswer: Int? = viewModel.answers[safe: index] ?? nil
                        let isCorrect = userAnswer == question.correctIndex
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("正确答案：\(question.options[question.correctIndex])")
                                    .foregroundStyle(.green)
                                if let answer = userAnswer {
                                    Text("你的选择：\(question.options[answer])")
                                        .foregroundStyle(isCorrect ? .green : .red)
                                } else {
                                    Text("你的选择：超时未答").foregroundStyle(.red)
                                }
                                Text(question.explanation)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.top, 6)
                        } label: {
                            HStack {
                                Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(isCorrect ? .green : .red)
                                Text(question.prompt)
                                    .font(.subheadline)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))

                // 操作按钮
                VStack(spacing: 12) {
                    Button {
                        viewModel.start()
                    } label: {
                        Text("再测一次")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)

                    Button("返回首页") {
                        viewModel.reset()
                    }
                    .foregroundStyle(.secondary)
                }

                Text("本测试结果基于固定题库与简化模型，仅供娱乐参考，不构成专业心理测评。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 20)
            }
            .padding(.horizontal, 24)
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#Preview {
    let vm = QuizViewModel()
    vm.start()
    vm.recordAnswer(0)
    vm.recordAnswer(nil)
    return ResultView()
        .environmentObject(vm)
}
