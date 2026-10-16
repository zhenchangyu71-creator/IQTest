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
    @EnvironmentObject private var viewModel: QuizViewModel
    @EnvironmentObject private var wechslerViewModel: WechslerViewModel

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            if wechslerViewModel.phase != .idle {
                switch wechslerViewModel.phase {
                case .stimulus, .question:
                    WechslerQuizView()
                case .finished:
                    WechslerResultView()
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
        .animation(.easeInOut(duration: 0.3), value: viewModel.phase)
        .animation(.easeInOut(duration: 0.3), value: wechslerViewModel.phase)
    }
}
