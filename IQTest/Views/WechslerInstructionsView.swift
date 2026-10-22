import SwiftUI

/// 完整练习与单项练习共享操作说明；准备好之前不启动计分题计时。
struct WechslerInstructionsView: View {
    @ObservedObject var vm: WechslerViewModel
    @State private var recall = ""
    @FocusState private var recallFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(vm.currentSubtest.rawValue).font(.largeTitle.bold())
                Text("操作说明 · 不计分示例")
                    .font(.headline).foregroundStyle(.purple)
                Text(vm.instructions.guidance)
                Text("本分测验 \(vm.itemsInSubtest) 题，每题作答限时 \(vm.currentSubtest.timeLimit) 秒。数字呈现时间另计。提交后进入下一题，计分题不即时反馈对错。")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("请在安静环境独立作答。现在可休息，准备好后再开始。")
                    .font(.subheadline)
                Divider()
                Text(vm.instructions.sample.prompt).font(.headline)
                if vm.instructions.sample.requiresRecall {
                    TextField("在此练习输入数字", text: $recall)
                        .keyboardType(.numberPad)
                        .focused($recallFocused)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("tutorialRecallInput")
                } else {
                    ForEach(vm.instructions.sample.options, id: \.self) { option in
                        Button { vm.answerTutorial(option) } label: {
                            Text(option)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("tutorialOption")
                        .disabled(vm.tutorialPassed)
                    }
                }
                if let feedback = vm.tutorialFeedback {
                    Label(feedback, systemImage: vm.tutorialPassed ? "checkmark.circle" : "info.circle")
                        .font(.subheadline)
                        .foregroundStyle(vm.tutorialPassed ? .green : .secondary)
                        .accessibilityIdentifier("tutorialFeedback")
                }
                Text("示例可重试，不计分，也不写入成绩。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if vm.instructions.sample.requiresRecall && !vm.tutorialPassed {
                    Button("核对示例") {
                        vm.answerTutorial(recall)
                        if vm.tutorialPassed { recallFocused = false }
                    }
                    .buttonStyle(.bordered).tint(.purple)
                    .accessibilityIdentifier("submitTutorial")
                    .disabled(vm.instructions.sample.recallScore(for: recall) == nil)
                }
                Button("开始本分测验") { vm.beginSubtest() }
                    .buttonStyle(.borderedProminent).tint(.purple)
                    .controlSize(.large)
                    .disabled(!vm.tutorialPassed)
                    .accessibilityIdentifier("startSubtest")
            }
            .frame(maxWidth: .infinity).padding()
            .background(.regularMaterial)
        }
    }
}
