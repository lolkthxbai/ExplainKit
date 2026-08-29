import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct ContentView: View {
    @State private var viewModel: DemoViewModel
    @State private var isModelImporterPresented = false
#if os(iOS)
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
#endif

    private static let liteRTModelType =
        UTType(filenameExtension: "litertlm") ?? .data

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        let configuration = DemoConfiguration(environment: environment)
        _viewModel = State(initialValue: DemoViewModel(configuration: configuration))
    }

    init(viewModel: DemoViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    DemoIntroductionView()

                    ForEach(DemoExampleGroup.allCases) { group in
                        VStack(alignment: .leading, spacing: 16) {
                            Text(group.title)
                                .font(.title2.bold())

                            if group == .gemini {
                                GeminiAvailabilityView(
                                    isConfigured: viewModel.isGeminiConfigured
                                )
                            }

                            if group == .onDeviceGemma {
                                LocalGemmaProvisioningView(
                                    state: viewModel.localGemmaState,
                                    selectionFailure: viewModel.importSelectionFailure,
                                    chooseModel: presentModelImporter
                                )
                            }

                            ForEach(group.scenarios) { scenario in
                                ScenarioCard(
                                    scenario: scenario,
                                    outcome: viewModel.outcomes[scenario],
                                    isRunning: viewModel.isRunning(scenario),
                                    fallbackTrigger: viewModel.fallbackTrigger(for: scenario),
                                    run: { run(scenario) }
                                )
                            }
                        }
                        .accessibilityElement(children: .contain)
                    }
                }
                .padding(24)
            }
            .navigationTitle("SwiftMend Demo")
#if os(iOS)
            .navigationBarTitleDisplayMode(
                dynamicTypeSize.isAccessibilitySize ? .inline : .large
            )
#endif
        }
        .task {
            await viewModel.restoreLocalModel()
        }
        .fileImporter(
            isPresented: $isModelImporterPresented,
            allowedContentTypes: [Self.liteRTModelType],
            allowsMultipleSelection: false,
            onCompletion: handleModelSelection
        )
    }

    private func run(_ scenario: DemoScenario) {
        Task {
            await viewModel.run(scenario)
        }
    }

    private func presentModelImporter() {
        isModelImporterPresented = true
    }

    private func handleModelSelection(
        _ result: Result<[URL], any Error>
    ) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                viewModel.reportImportSelectionFailure()
                return
            }
            Task {
                await viewModel.importLocalModel(from: url)
            }
        case .failure(let error):
            guard (error as? CocoaError)?.code != .userCancelled else { return }
            viewModel.reportImportSelectionFailure()
        }
    }
}

#Preview {
    ContentView(environment: [:])
#if os(macOS)
        .frame(width: 800, height: 900)
#endif
}
