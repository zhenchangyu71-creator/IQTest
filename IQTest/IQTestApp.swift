import SwiftUI

@main
struct IQTestApp: App {
    @StateObject private var viewModel = QuizViewModel()
    @StateObject private var wechslerViewModel = WechslerViewModel()
    @StateObject private var practiceViewModel = PracticeViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .environmentObject(wechslerViewModel)
                .environmentObject(practiceViewModel)
        }
    }
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var viewModel: QuizViewModel
    @EnvironmentObject private var wechslerViewModel: WechslerViewModel
    @EnvironmentObject private var practiceViewModel: PracticeViewModel

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            if wechslerViewModel.phase != .idle {
                switch wechslerViewModel.phase {
                case .briefing:
                    WechslerInstructionsView(vm: wechslerViewModel).id(wechslerViewModel.currentSubtest)
                case .interrupted:
                    WechslerInterruptionView(vm: wechslerViewModel)
                case .stimulus, .question:
                    WechslerQuizView()
                case .finished:
                    WechslerResultView()
                case .failed:
                    VStack(spacing: 16) {
                        Text(wechslerViewModel.errorMessage ?? "题库暂不可用")
                            .multilineTextAlignment(.center)
                        Button("返回首页") { wechslerViewModel.reset() }
                    }.padding()
                case .idle:
                    EmptyView()
                }
            } else {
                switch viewModel.phase {
                case .ready:
                    WelcomeView()
                case .inProgress:
                    QuizView()
                case .finished:
                    ResultView()
                }
            }
        }
        .safeAreaInset(edge: .top) {
            if [.briefing, .stimulus, .question, .interrupted].contains(wechslerViewModel.phase) {
                endButton { wechslerViewModel.endAndSave() }
            } else if viewModel.phase == .inProgress {
                endButton { viewModel.endAndSave() }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.phase)
        .animation(.easeInOut(duration: 0.3), value: wechslerViewModel.phase)
        .onChange(of: scenePhase, initial: true) { _, phase in
            wechslerViewModel.setAppActive(phase == .active)
            practiceViewModel.setAppActive(phase == .active)
        }
    }

    private func endButton(_ action: @escaping () -> Void) -> some View {
        HStack {
            Spacer()
            Button("结束并保存已答题", action: action)
                .font(.footnote).foregroundStyle(.purple)
                .accessibilityIdentifier("endSession")
        }.padding(.horizontal).padding(.vertical, 8).background(.regularMaterial)
    }
}
