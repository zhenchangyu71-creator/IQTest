import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject private var viewModel: QuizViewModel
    @EnvironmentObject private var wechslerViewModel: WechslerViewModel
    @EnvironmentObject private var practiceViewModel: PracticeViewModel
    @State private var showHistory = false
    @State private var showPractice = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer(minLength: 12)

                Image(systemName: "brain.head.profile")
                    .font(.system(size: 60))
                    .foregroundStyle(.purple, .indigo)

                Text("智商测试")
                    .font(.largeTitle.bold())

                Text(viewModel.testType == .raven
                     ? "12 道题 · 四大维度 · 三种难度\n测测你的逻辑与推理能力"
                     : "10 个分测验 · 120 个项目\n参照韦氏标准施测流程")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                // 测评体系选择
                VStack(alignment: .leading, spacing: 10) {
                    Text("测评体系")
                        .font(.headline)
                        .padding(.horizontal, 4)
                    ForEach(TestType.allCases) { type in
                        let selected = viewModel.testType == type
                        Button {
                            viewModel.testType = type
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: type.systemImage)
                                    .font(.title3)
                                    .foregroundStyle(.white)
                                    .frame(width: 36, height: 36)
                                    .background(Color.indigo.gradient, in: RoundedRectangle(cornerRadius: 8))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(type.rawValue)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text(type.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected ? Color.purple : .secondary)
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(selected ? Color.purple.opacity(0.10) : Color(.secondarySystemGroupedBackground))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(selected ? Color.purple : .clear, lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground).opacity(0.5), in: RoundedRectangle(cornerRadius: 16))

                // 被试信息：年龄用于按年龄常模校准换算
                VStack(alignment: .leading, spacing: 10) {
                    Text("被试信息")
                        .font(.headline)
                        .padding(.horizontal, 4)
                    HStack(spacing: 12) {
                        Image(systemName: "person.fill")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(.purple.gradient, in: RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("年龄")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text("用于按年龄常模校准智商换算")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(viewModel.age) 岁")
                            .font(.headline)
                            .monospacedDigit()
                        Stepper(value: $viewModel.age, in: 6...99) {
                            Text("\(viewModel.age) 岁")
                        }
                        .labelsHidden()
                        .accessibilityLabel("年龄步进器，当前 \(viewModel.age) 岁")
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground).opacity(0.5), in: RoundedRectangle(cornerRadius: 16))

                // 难度选择（韦氏标准流程不分难度，隐藏）
                if viewModel.testType == .raven {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("选择难度")
                            .font(.headline)
                            .padding(.horizontal, 4)
                        ForEach(Difficulty.allCases) { level in
                            let selected = viewModel.difficulty == level
                            Button {
                                viewModel.difficulty = level
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: level.icon)
                                        .font(.title3)
                                        .foregroundStyle(.white)
                                        .frame(width: 36, height: 36)
                                        .background(iconColor(level).gradient, in: RoundedRectangle(cornerRadius: 8))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(level.rawValue)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        Text(level.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if viewModel.bestScore(for: level) > 0 {
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text("最佳 \(viewModel.bestScore(for: level))/12")
                                                .font(.caption.monospacedDigit())
                                                .foregroundStyle(.secondary)
                                            Text("IQ \(viewModel.bestIQ(for: level))")
                                                .font(.caption.bold())
                                                .foregroundStyle(.orange)
                                        }
                                    }
                                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selected ? Color.purple : .secondary)
                                }
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(selected ? Color.purple.opacity(0.10) : Color(.secondarySystemGroupedBackground))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(selected ? Color.purple : .clear, lineWidth: 1.5)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground).opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
                }

                // 测评内容（瑞文：四大维度；韦氏：10 个分测验）
                if viewModel.testType == .raven {
                    VStack(spacing: 12) {
                        ForEach(viewModel.testType.categories) { category in
                            HStack(spacing: 12) {
                                Image(systemName: category.systemImage)
                                    .font(.title3)
                                    .foregroundStyle(.white)
                                    .frame(width: 36, height: 36)
                                    .background(Color.purple.gradient, in: RoundedRectangle(cornerRadius: 8))
                                Text(category.rawValue)
                                    .font(.headline)
                                Spacer()
                                Text("3 题/级")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("10 个分测验（标准施测顺序）")
                            .font(.headline)
                            .padding(.horizontal, 4)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(WechslerSubtest.allCases) { subtest in
                                Label(subtest.rawValue, systemImage: "circle.fill")
                                    .font(.caption.bold())
                                    .foregroundStyle(.primary)
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity)
                                    .background(Color(.secondarySystemGroupedBackground).opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                    .padding(.vertical)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                }

                // 分测验练习入口（韦氏体系专属）
                if viewModel.testType == .wechsler {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("单项训练")
                            .font(.headline)
                            .padding(.horizontal, 4)
                        Button {
                            showPractice = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "target")
                                    .font(.title3)
                                    .foregroundStyle(.white)
                                    .frame(width: 36, height: 36)
                                    .background(Color.indigo.gradient, in: RoundedRectangle(cornerRadius: 8))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("分测验练习")
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text("任选 1 个分测验练 3 题 · 跟踪最佳量表分")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("分测验练习")
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground).opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
                }

                VStack(spacing: 8) {
                    if viewModel.testType == .raven {
                        Label("每轮 12 题，题目与选项每次随机打乱", systemImage: "shuffle")
                        Label("每题限时见所选难度，超时视为未答", systemImage: "clock")
                    } else {
                        Label("分测验按标准顺序施测，项目按难度递进", systemImage: "list.number")
                        Label("同一分测验连续答错 3 题提前结束该分测验", systemImage: "hand.raised")
                        Label("言语分测验按 0/1/2 计分，操作分测验按 0/1 计分", systemImage: "star")
                    }
                    Label("结果仅供娱乐参考", systemImage: "info.circle")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)

                Button {
                    if viewModel.testType == .wechsler {
                        wechslerViewModel.start()
                    } else {
                        viewModel.start()
                    }
                } label: {
                    Text(viewModel.testType == .raven
                         ? "开始瑞文\(viewModel.difficulty.rawValue)测试"
                         : "开始韦氏标准测验")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)

                Button {
                    showHistory = true
                } label: {
                    Label("历史成绩", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.subheadline.bold())
                }
                .buttonStyle(.bordered)
                .tint(.purple)

                Spacer(minLength: 12)
            }
            .padding(.horizontal, 24)
            .sheet(isPresented: $showHistory) {
                HistoryView()
            }
            .fullScreenCover(isPresented: $showPractice) {
                SubtestPracticeView()
                    .environmentObject(practiceViewModel)
            }
            .onAppear {
                // 调试：以 -showHistory 启动参数打开时直接进入历史页
                if CommandLine.arguments.contains("-showHistory") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        showHistory = true
                    }
                }
            }
        }
    }

    private func iconColor(_ level: Difficulty) -> Color {
        switch level {
        case .easy: return .green
        case .medium: return .orange
        case .hard: return .red
        }
    }
}

#Preview {
    WelcomeView()
        .environmentObject(QuizViewModel())
        .environmentObject(WechslerViewModel())
}
