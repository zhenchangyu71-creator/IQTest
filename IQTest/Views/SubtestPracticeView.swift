import SwiftUI

/// 分测验练习：选分测验 → 答 3 题 → 估计量表分 + 历史最佳
struct SubtestPracticeView: View {
    @EnvironmentObject private var vm: PracticeViewModel
    @Environment(\.dismiss) private var dismiss

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            Group {
                switch vm.phase {
                case .picker:
                    pickerView
                case .stimulus, .question:
                    quizView
                case .done:
                    resultView
                }
            }
            .navigationTitle("分测验练习")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .onReceive(timer) { _ in
            vm.tick()
        }
    }

    // MARK: - 选分测验

    private var pickerView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // 能力雷达图：各分测验最佳量表分
                PracticeRadarView(scores: WechslerSubtest.allCases.map { PracticeStore.best(subtest: $0) })
                    .padding(.vertical, 4)

                Text("任选一个分测验练 3 题（低、中、高难度各 1 题），跟踪你的最佳量表分。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(WechslerSubtest.allCases) { subtest in
                        Button {
                            vm.start(subtest)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(subtest.rawValue)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text(subtest.domain.shortName + " · " + (subtest.maxPointsPerItem == 2 ? "0/1/2 计分" : "0/1 计分"))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                let count = PracticeStore.count(subtest: subtest)
                                if count > 0 {
                                    HStack(spacing: 4) {
                                        Image(systemName: "chart.bar.fill")
                                        Text("练过 \(count) 次 · 最佳 \(PracticeStore.best(subtest: subtest)) 分")
                                    }
                                    .font(.caption2.bold())
                                    .foregroundStyle(.orange)
                                } else {
                                    Text("未练习过")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(subtest.rawValue) 分测验")
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - 答题（复用标准施测的呈现方式）

    private var quizView: some View {
        VStack(spacing: 16) {
            HStack {
                Label(vm.subtest.rawValue, systemImage: "target")
                    .font(.subheadline.bold())
                    .foregroundStyle(.purple)
                Spacer()
                Text("第 \(vm.itemNumber) / \(vm.itemCount) 题")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if vm.phase != .stimulus {
                    Label("\(vm.timeRemaining)s", systemImage: "timer")
                        .font(.subheadline.bold())
                        .foregroundStyle(vm.timeRemaining <= 10 ? .red : .secondary)
                }
            }

            ProgressView(value: vm.progress)
                .tint(.purple)

            if vm.phase == .stimulus, let item = vm.currentItem {
                stimulusView(item: item)
            } else if vm.phase == .question, let item = vm.currentItem {
                questionView(item: item)
            }

            Spacer()
        }
        .padding()
    }

    private func stimulusView(item: WechslerItem) -> some View {
        VStack(spacing: 24) {
            Spacer()
            Text("请记住以下数字")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(item.stimulus ?? "")
                .font(.system(size: 44, weight: .bold, design: .monospaced))
                .tracking(12)
                .foregroundStyle(.primary)
                .padding()
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            Text("\(vm.stimulusRemaining) 秒后开始作答")
                .font(.subheadline)
                .foregroundStyle(.purple)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func questionView(item: WechslerItem) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(item.prompt)
                .font(.title3.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))

            VStack(spacing: 12) {
                ForEach(vm.presentedOptions) { option in
                    Button {
                        vm.record(option.score)
                    } label: {
                        Text(option.text)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
    }

    // MARK: - 练习结果

    private var resultView: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Text(vm.subtest.rawValue + " · 练习结果")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("\(vm.estimatedScaled)")
                        .font(.system(size: 84, weight: .bold, design: .rounded))
                        .foregroundStyle(.purple)
                    Text("估计量表分（满分 19）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("原始分 \(vm.rawScore)/\(vm.maxRaw) · 按 \(AgeBand.current.title) 年龄常模校准（简化）")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(vm.scaledComment)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))

                VStack(spacing: 12) {
                    Button {
                        vm.start(vm.subtest)
                    } label: {
                        Text("再练一组")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.purple, in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.white)
                    }
                    Button {
                        vm.backToPicker()
                    } label: {
                        Text("选择其他分测验")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.primary)
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }
}
