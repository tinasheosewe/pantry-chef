import SwiftUI

struct CookModeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    /// Both are created lazily on first appear — no heavy AV objects at app launch.
    @State private var speechService: SpeechService?
    @State private var viewModel: CookModeViewModel?

    private let recipe: Recipe

    init(recipe: Recipe) {
        self.recipe = recipe
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let viewModel {
                cookContent(vm: viewModel)
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if viewModel == nil {
                let service = SpeechService()
                speechService = service
                viewModel = CookModeViewModel(recipe: recipe, speechService: service)
            }
            viewModel?.speakCurrentStep()
        }
        .onDisappear {
            viewModel?.cleanup()
        }
        .alert("Voice Control Unavailable",
               isPresented: Binding(
                get: { viewModel?.voiceAuthorizationDenied ?? false },
                set: { viewModel?.voiceAuthorizationDenied = $0 }
               )) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Please enable Speech Recognition and Microphone access in Settings to use voice commands.")
        }
    }

    // MARK: - Cook Content

    @ViewBuilder
    private func cookContent(vm: CookModeViewModel) -> some View {
        if vm.showCompletionScreen {
            completionView(vm: vm)
        } else {
            VStack(spacing: 0) {
                topBar(vm: vm)
                progressBar(vm: vm)

                TabView(selection: Bindable(vm).currentStepIndex) {
                    ForEach(Array(vm.steps.enumerated()), id: \.element.id) { index, step in
                        stepView(step)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                if vm.currentStep?.timerMinutes != nil || vm.isTimerRunning {
                    timerView(vm: vm)
                }

                navigationControls(vm: vm)

                if vm.isVoiceControlEnabled {
                    voiceControlIndicator()
                }
            }
        }
    }

    // MARK: - Top Bar

    private func topBar(vm: CookModeViewModel) -> some View {
        HStack {
            Button {
                vm.cleanup()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.title3)
                    .foregroundStyle(.white)
            }

            Spacer()

            Text(vm.recipe.title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer()

            Button {
                vm.toggleAudio()
            } label: {
                Image(systemName: vm.isAudioEnabled ? "speaker.wave.3.fill" : "speaker.slash.fill")
                    .font(.title3)
                    .foregroundStyle(vm.isAudioEnabled ? AppColors.primaryGreen : .gray)
            }
        }
        .padding()
    }

    // MARK: - Progress Bar

    private func progressBar(vm: CookModeViewModel) -> some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.white.opacity(0.15))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(AppColors.primaryGreen)
                        .frame(width: geo.size.width * vm.progress)
                        .animation(.easeInOut(duration: 0.3), value: vm.progress)
                }
            }
            .frame(height: 4)

            Text("Step \(vm.currentStepIndex + 1) of \(vm.steps.count)")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.horizontal)
    }

    // MARK: - Step View

    private func stepView(_ step: RecipeStep) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 40)

                Text("STEP \(step.stepNumber)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .tracking(2)
                    .foregroundStyle(AppColors.primaryGreen)

                Text(step.instruction)
                    .font(.title2)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .lineSpacing(4)

                if let timer = step.timerMinutes {
                    HStack(spacing: 8) {
                        Image(systemName: "timer")
                            .foregroundStyle(AppColors.warmOrange)
                        Text("\(timer) minutes")
                            .fontWeight(.medium)
                            .foregroundStyle(AppColors.warmOrange)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(AppColors.warmOrange.opacity(0.15))
                    .clipShape(Capsule())
                }

                if let tip = step.tip {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "lightbulb.fill")
                                .foregroundStyle(.yellow)
                            Text("Beginner Tip")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.yellow)
                        }
                        Text(tip)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding()
                    .background(.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 24)
                }

                Spacer(minLength: 40)
            }
        }
    }

    // MARK: - Timer View

    private func timerView(vm: CookModeViewModel) -> some View {
        VStack(spacing: 8) {
            if vm.isTimerRunning {
                HStack(spacing: 16) {
                    Text(vm.timerDisplay)
                        .font(.system(size: 48, weight: .light, design: .monospaced))
                        .foregroundStyle(vm.timerSeconds <= 10 ? AppColors.softRed : AppColors.primaryGreen)

                    VStack(spacing: 8) {
                        Button {
                            vm.pauseTimer()
                        } label: {
                            Image(systemName: vm.isPaused ? "play.fill" : "pause.fill")
                                .font(.title3)
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(.white.opacity(0.15))
                                .clipShape(Circle())
                        }

                        Button {
                            vm.stopTimer()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.6))
                                .frame(width: 32, height: 32)
                                .background(.white.opacity(0.1))
                                .clipShape(Circle())
                        }
                    }
                }
                .padding()
                .background(.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            } else if vm.currentStep?.timerMinutes != nil {
                Button {
                    vm.startTimer()
                } label: {
                    Label("Start Timer", systemImage: "timer")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(AppColors.warmOrange)
                        .clipShape(Capsule())
                }
            }
        }
        .padding()
    }

    // MARK: - Navigation Controls

    private func navigationControls(vm: CookModeViewModel) -> some View {
        HStack(spacing: 32) {
            Button {
                vm.previousStep()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(vm.isFirstStep ? .gray.opacity(0.3) : .white)
                    Text("Back")
                        .font(.caption2)
                        .foregroundStyle(vm.isFirstStep ? .gray.opacity(0.3) : .white.opacity(0.6))
                }
            }
            .disabled(vm.isFirstStep)

            Button {
                vm.speakCurrentStep()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.white.opacity(0.6))
                    Text("Repeat")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            Button {
                if vm.isVoiceControlEnabled {
                    vm.stopVoiceControl()
                } else {
                    vm.startVoiceControl()
                }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: vm.isVoiceControlEnabled ? "mic.fill" : "mic.slash")
                        .font(.system(size: 44))
                        .foregroundStyle(vm.isVoiceControlEnabled ? AppColors.primaryGreen : .white.opacity(0.6))
                    Text("Voice")
                        .font(.caption2)
                        .foregroundStyle(vm.isVoiceControlEnabled ? AppColors.primaryGreen : .white.opacity(0.6))
                }
            }

            Button {
                vm.nextStep()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: vm.isLastStep ? "checkmark.circle.fill" : "chevron.right.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(vm.isLastStep ? AppColors.primaryGreen : .white)
                    Text(vm.isLastStep ? "Done" : "Next")
                        .font(.caption2)
                        .foregroundStyle(vm.isLastStep ? AppColors.primaryGreen : .white.opacity(0.6))
                }
            }
        }
        .padding()
        .padding(.bottom, 8)
    }

    // MARK: - Voice Control Indicator

    private func voiceControlIndicator() -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Circle()
                    .fill(AppColors.primaryGreen)
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle()
                            .fill(AppColors.primaryGreen.opacity(0.4))
                            .scaleEffect(1.5)
                    )
                    .modifier(PulseAnimation())
                Text("Listening... Say \"next\", \"back\", \"repeat\", or \"pause\"")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            if let text = speechService?.recognizedText, !text.isEmpty {
                Text("\"\(text)\"")
                    .font(.caption2)
                    .foregroundStyle(AppColors.primaryGreen.opacity(0.8))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.bottom, 8)
    }

    // MARK: - Completion View

    private func completionView(vm: CookModeViewModel) -> some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(AppColors.primaryGreen)

            Text("Well Done!")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(.white)

            Text("You've completed \(vm.recipe.title)")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)

            VStack(spacing: 8) {
                Text("How was it?")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))

                HStack(spacing: 8) {
                    ForEach(1...5, id: \.self) { star in
                        Button {
                            vm.setRating(star)
                        } label: {
                            Image(systemName: star <= (vm.selectedRating ?? 0) ? "star.fill" : "star")
                                .font(.title2)
                                .foregroundStyle(star <= (vm.selectedRating ?? 0) ? .yellow : .white.opacity(0.3))
                        }
                    }
                }
            }

            Spacer()

            VStack(spacing: 12) {
                Button {
                    Task {
                        // Save rating if set, then mark as cooked
                        if vm.selectedRating != nil {
                            await appState.updateRecipe(vm.ratedRecipe)
                        }
                        await appState.markRecipeAsCooked(vm.recipe)
                    }
                    dismiss()
                } label: {
                    Text("Done — Update Pantry")
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(AppColors.primaryGreen)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                Button {
                    dismiss()
                } label: {
                    Text("Close")
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }
}

// MARK: - Pulse Animation

private struct PulseAnimation: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.3 : 1.0)
            .opacity(isPulsing ? 0.6 : 1.0)
            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}