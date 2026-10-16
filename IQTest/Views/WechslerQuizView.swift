import SwiftUI

struct WechslerQuizView: View {
    @EnvironmentObject private var vm: WechslerViewModel

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 16) {
            // 顶部：分测验 + 进度 + 计时
            HStack {
                Label(vm.currentSubtest.rawValue, systemImage: "list.number")
                    .font(.subheadline.bold())
                    .foregroundStyle(.purple)
                Spacer()
                Text("第 \(vm.itemNumber) / \(vm.itemsInSubtest) 题")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if vm.phase != .stimulus {
                    Label("\(vm.timeRemaining)s", systemImage: "timer")
                        .font(.subheadline.bold())
                        .foregroundStyle(vm.timeRemaining <= 10 ? .red : .secondary)
                }
            }

            ProgressView(value: vm.totalProgress)
                .tint(.purple)

            if vm.phase == .stimulus, let item = vm.currentItem {
                stimulusView(item: item)
            } else if vm.phase == .question, let item = vm.currentItem {
                questionView(item: item)
            }

            Spacer()
        }
        .padding()
        .onReceive(timer) { _ in
            vm.tick()
        }
    }

    // MARK: - 数字广度：刺激呈现阶段

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

    // MARK: - 作答阶段（标准施测不反馈对错，直接下一题）

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
}
