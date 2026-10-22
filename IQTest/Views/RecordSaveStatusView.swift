import SwiftUI

struct RecordSaveStatusView: View {
    let error: String?
    let retry: () -> Void
    var body: some View {
        if let error {
            VStack(alignment: .leading, spacing: 8) {
                Text("本次记录尚未保存").font(.headline)
                Text(error).font(.footnote)
                Text("可以重试，或先将本次成绩导出为 JSON。离开结果页会清理未保存内容。")
                    .font(.caption)
                Button("重试保存", action: retry).accessibilityIdentifier("retryRecordSave")
            }
            .padding().foregroundStyle(.red)
            .background(Color.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

struct ResultExitActions: View {
    let hasUnsavedRecord: Bool
    let again: () -> Void
    let home: () -> Void
    @State private var leaving = false
    @State private var repeating = false
    var body: some View {
        Button("再练一次") { request(repeatRun: true) }
            .buttonStyle(.borderedProminent).tint(.purple)
        Button("返回首页") { request(repeatRun: false) }.foregroundStyle(.secondary)
            .confirmationDialog("本次记录尚未保存，仍要离开吗？", isPresented: $leaving, titleVisibility: .visible) {
                Button("放弃未保存记录并离开", role: .destructive) { repeating ? again() : home() }
                Button("继续保留", role: .cancel) {}
            }
    }
    private func request(repeatRun: Bool) {
        repeating = repeatRun
        if hasUnsavedRecord { leaving = true }
        else { repeatRun ? again() : home() }
    }
}
