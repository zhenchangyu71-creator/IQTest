import SwiftUI

struct QuizView: View {
    @EnvironmentObject private var viewModel: QuizViewModel
    @State private var selectedIndex: Int? = nil

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 16) {
            // 顶部：进度 + 计时
            HStack {
                Text("第 \(min(viewModel.currentIndex + 1, viewModel.questions.count)) / \(viewModel.questions.count) 题")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Label("\(viewModel.timeRemaining)s", systemImage: "timer")
                    .font(.subheadline.bold())
                    .foregroundStyle(viewModel.timeRemaining <= 10 ? .red : .secondary)
                Text("/ \(viewModel.secondsPerQuestion)s")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            ProgressView(value: viewModel.progress)
                .tint(.purple)

            // 题干
            if let question = viewModel.currentQuestion {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: question.category.systemImage)
                        Text(question.category.rawValue)
                    }
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.purple, in: Capsule())

                    Text(question.prompt)
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))

                // 选项
                VStack(spacing: 12) {
                    ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                        Button {
                            choose(index)
                        } label: {
                            HStack {
                                Text(option)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selectedIndex != nil {
                                    Image(systemName: icon(for: index, question: question))
                                        .foregroundStyle(color(for: index, question: question))
                                }
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(fill(for: index, question: question))
                            )
                        }
                        .disabled(selectedIndex != nil)
                    }
                }
            }

            Spacer()
        }
        .padding()
        .onReceive(timer) { _ in
            viewModel.tick()
        }
    }

    private func choose(_ index: Int) {
        guard selectedIndex == nil else { return }
        selectedIndex = index
        // 短暂展示对错后进入下一题
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            viewModel.recordAnswer(index)
            selectedIndex = nil
        }
    }

    private func fill(for index: Int, question: Question) -> Color {
        guard let selected = selectedIndex else {
            return Color(.secondarySystemGroupedBackground)
        }
        if index == question.correctIndex { return Color.green.opacity(0.25) }
        if index == selected { return Color.red.opacity(0.25) }
        return Color(.secondarySystemGroupedBackground)
    }

    private func color(for index: Int, question: Question) -> Color {
        if index == question.correctIndex { return .green }
        if index == selectedIndex { return .red }
        return .clear
    }

    private func icon(for index: Int, question: Question) -> String {
        if index == question.correctIndex { return "checkmark.circle.fill" }
        if index == selectedIndex { return "xmark.circle.fill" }
        return "circle"
    }
}

#Preview {
    let vm = QuizViewModel()
    vm.start()
    return QuizView()
        .environmentObject(vm)
}
