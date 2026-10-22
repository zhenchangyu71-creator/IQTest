import SwiftUI

struct WechslerInterruptionView: View {
    @ObservedObject var vm: WechslerViewModel

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "pause.circle").font(.system(size: 48)).foregroundStyle(.purple)
            Text("练习已中断").font(.title.bold())
            if vm.interruptedItemExpired {
                Text("应用离开前台时，当前项目已到作答截止时刻，仍按超时计 0 分。已答项目保留，确认继续后才呈现下一题。")
            } else {
                Text("应用离开前台，当前项目的呈现或作答条件受到影响。已答项目保留，当前项目将标记为中断、排除出得分率分母。")
                Text("确认继续后才呈现下一题。本次可查看题目成绩，但不生成 IQ 估算，也不更新单项练习最佳成绩。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Button("继续下一题") { vm.resumeAfterInterruption() }
                .buttonStyle(.borderedProminent).tint(.purple).controlSize(.large)
        }
        .multilineTextAlignment(.center)
        .padding(28)
    }
}

struct WechslerAdministrationView: View {
    let administration: WechslerAdministration

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("过程记录").font(.headline)
            Text("已完成 \(administration.completedTutorials.count) 个分测验操作示例，示例不计分。")
            Text(administration.hasPriorExposure ? "本机已有练习或复测记录。" : "开始前本机未记录到既往练习。")
            if administration.interruptions.isEmpty {
                Text("计分题期间未记录到应用离开前台。")
            } else {
                let seconds = administration.interruptions.reduce(0) { $0 + $1.inactiveSeconds }
                Text("中断 \(administration.interruptions.count) 题 · 离开前台共 \(Int(seconds.rounded())) 秒")
                Text("中断题未计分。得分率仅描述其余题目，不能与完整作答直接比较。")
            }
            Text("过程记录不代表测量效度已获验证。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }
}
