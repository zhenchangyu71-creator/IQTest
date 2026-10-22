import SwiftUI

/// 分测验练习：选分测验 → 答 3 题 → 原始成绩 + 逐题解析
struct SubtestPracticeView: View {
    @EnvironmentObject private var vm: PracticeViewModel
    @Environment(\.dismiss) private var dismiss

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            Group {
                switch vm.phase {
                case .idle:
                    pickerView
                case .briefing:
                    WechslerInstructionsView(vm: vm).id(vm.currentSubtest)
                case .interrupted:
                    WechslerInterruptionView(vm: vm)
                case .stimulus, .question:
                    quizView
                case .finished:
                    resultView
                case .failed:
                    VStack(spacing: 16) {
                        Text(vm.errorMessage ?? "题库暂不可用")
                        Button("返回选择") { vm.backToPicker() }
                    }.padding()
                }
            }
            .navigationTitle("分测验练习")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { vm.backToPicker(); dismiss() }
                }
            }
        }
        .onReceive(timer) { _ in
            vm.tick()
        }
        .onDisappear { vm.backToPicker() }
    }

    // MARK: - 选分测验

    private var pickerView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // 能力雷达图：各分测验最佳练习得分率
                PracticeRadarView(scores: WechslerSubtest.allCases.map { PracticeStore.best(subtest: $0) })
                    .padding(.vertical, 4)

                Text("从题库前、中、后三段各抽 1 题，共练 3 题。得分率只描述这组题，不代表同龄人水平。")
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
                                        Text("练过 \(count) 次 · 最佳 \(PracticeStore.best(subtest: subtest) ?? 0)%")
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

    // MARK: - 答题（与完整练习共用计时和作答逻辑）

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
            Text(item.prompt)
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(item.stimulus ?? "")
                .font(.system(size: 32, weight: .bold, design: .monospaced))
                .tracking(2)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
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

            if item.requiresRecall {
                RecallAnswerView(item: item) { vm.submitRecall($0, for: item.id) }
                    .id(item.id)
            }
            VStack(spacing: 12) {
                ForEach(vm.presentedOptions) { option in
                    Button {
                        vm.choose(optionID: option.id, for: item.id)
                    } label: {
                        Text(option.text)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .accessibilityIdentifier("wechslerOption")
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
                    Text(vm.maxRaw > 0 ? "\(vm.performancePercentage)%" : "—")
                        .font(.system(size: 84, weight: .bold, design: .rounded))
                        .foregroundStyle(.purple)
                    Text("本组题目得分率")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("原始分 \(vm.rawScore)/\(vm.maxRaw) · 超时 \(vm.timedOutCount) 题 · 中断 \(vm.interruptedCount) 题")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(vm.performanceComment)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))

                WechslerAdministrationView(administration: vm.administration)
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))

                WechslerReviewView(responses: vm.responses, item: vm.item(for:))
                Text(WechslerLoader.scoringNotice).font(.caption).foregroundStyle(.secondary)

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
