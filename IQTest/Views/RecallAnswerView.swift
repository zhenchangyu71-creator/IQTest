import SwiftUI

/// 数字广度采用自由输入，避免备选项将回忆任务变成识别任务。
struct RecallAnswerView: View {
    let item: WechslerItem
    let submit: (String) -> Void
    @State private var answer = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("输入回忆的数字", text: $answer)
                .keyboardType(.numberPad)
                .focused($isFocused)
                .onAppear { isFocused = true }
                .textFieldStyle(.roundedBorder)
                .font(.title2.monospacedDigit())
                .accessibilityIdentifier("digitRecallInput")
            Button("提交回忆") { submit(answer) }
                .buttonStyle(.borderedProminent).tint(.purple)
                .disabled(item.recallScore(for: answer) == nil)
            Text("按题干要求输入完整序列，可使用空格分隔。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
