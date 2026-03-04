import SwiftUI

struct CookModeView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel: CookModeViewModel

    init(recipe: Recipe) {
        _viewModel = StateObject(wrappedValue: CookModeViewModel(
            recipe: recipe,
            speechService: SpeechService()
        ))
    }

    var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()

            if viewModel.showCompletionScreen {
                completionView
            } else {
                VStack(spacing: 0) {
                    // Top bar
                    topBar

                    // Progress bar
                    progressBar

                    // Main content
                    TabView(selection: $viewModel.currentStepIndex) {
                        ForEach(Array(viewModel.steps.enumerated()), id: \.element.id) { index, step in
                            stepView(step)
                                .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))

                    // Timer (if applicable)
                    if viewModel.currentStep?.timerMinutes != nil || viewModel.isTimerRunning {
                        timerView
                    }

                    // Navigation controls
                    navigationControls

                    // Voice control indicator
                    if viewModel.isVoiceControlEnabled {
                        voiceControlIndicator
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            viewModel.speakCurrentStep()
        }
        .onDisappear {
            viewModel.cleanup()
        }
    }

    // MARK: - Top Bar
    private var topBar: some View {
        HStack {
            Button {
                viewModel.cleanup()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.title3)
                    .foregroundStyle(.white)
            }

            Spacer()

            Text(viewModel.recipe.title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer()

            // Audio toggle
            Button {
                viewModel.toggleAudio()
            } label: {
                Image(systemName: viewModel.isAudioEnabled ? "speaker.wave.3.fill" : "speaker.slash.fill")
                    .font(.title3)
                    .foregroundStyle(viewModel.isAudioEnabled ? AppColors.primaryGreen : .gray)
            }
        }
        .padding()
    }

    // MARK: - Progress Bar
    private var progressBar: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.white.opacity(0.15))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(AppColors.primaryGreen)
                        .frame(width: geo.size.width * viewModel.progress)
                        .animation(.easeInOut(duration: 0.3), value: viewModel.progress)
                }
            }
            .frame(height: 4)

            Text("Step \(viewModel.currentStepIndex + 1) of \(viewModel.steps.count)")
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

                // Step number
                Text("STEP \(step.stepNumber)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .tracking(2)
                    .foregroundStyle(AppColors.primaryGreen)

                // Instruction
                Text(step.instruction)
                    .font(.title2)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .lineSpacing(4)

                // Timer badge
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

                // Tip
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
    private var timerView: some View {
        VStack(spacing: 8) {
            if viewModel.isTimerRunning {
                HStack(spacing: 16) {
                    Text(viewModel.timerDisplay)
                        .font(.system(size: 48, weight: .light, design: .monospaced))
                        .foregroundStyle(viewModel.timerSeconds <= 10 ? AppColors.softRed : AppColors.primaryGreen)

                    VStack(spacing: 8) {
                        Button {
                            viewModel.pauseTimer()
                        } label: {
                            Image(systemName: viewModel.isPaused ? "play.fill" : "pause.fill")
                                .font(.title3)
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(.white.opacity(0.15))
                                .clipShape(Circle())
                        }

                        Button {
                            viewModel.stopTimer()
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
            } else if viewModel.currentStep?.timerMinutes != nil {
                Button {
                    viewModel.startTimer()
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
    private var navigationControls: some View {
        HStack(spacing: 32) {
            // Previous
            Button {
                viewModel.previousStep()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(viewModel.isFirstStep ? .gray.opacity(0.3) : .white)
                    Text("Back")
                        .font(.caption2)
                        .foregroundStyle(viewModel.isFirstStep ? .gray.opacity(0.3) : .white.opacity(0.6))
                }
            }
            .disabled(viewModel.isFirstStep)

            // Repeat
            Button {
                viewModel.speakCurrentStep()
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

            // Voice control toggle
            Button {
                if viewModel.isVoiceControlEnabled {
                    viewModel.stopVoiceControl()
                } else {
                    viewModel.startVoiceControl()
                }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: viewModel.isVoiceControlEnabled ? "mic.fill" : "mic.slash")
                        .font(.system(size: 44))
                        .foregroundStyle(viewModel.isVoiceControlEnabled ? AppColors.primaryGreen : .white.opacity(0.6))
                    Text("Voice")
                        .font(.caption2)
                        .foregroundStyle(viewModel.isVoiceControlEnabled ? AppColors.primaryGreen : .white.opacity(0.6))
                }
            }

            // Next
            Button {
                viewModel.nextStep()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: viewModel.isLastStep ? "checkmark.circle.fill" : "chevron.right.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(viewModel.isLastStep ? AppColors.primaryGreen : .white)
                    Text(viewModel.isLastStep ? "Done" : "Next")
                        .font(.caption2)
                        .foregroundStyle(viewModel.isLastStep ? AppColors.primaryGreen : .white.opacity(0.6))
                }
            }
        }
        .padding()
        .padding(.bottom, 8)
    }

    // MARK: - Voice Control Indicator
    private var voiceControlIndicator: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(AppColors.primaryGreen)
                .frame(width: 8, height: 8)
                .overlay(
                    Circle()
                        .fill(AppColors.primaryGreen.opacity(0.4))
                        .scaleEffect(1.5)
                )
            Text("Listening... Say \"next\", \"back\", or \"repeat\"")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.white.opacity(0.08))
        .clipShape(Capsule())
        .padding(.bottom, 8)
    }

    // MARK: - Completion View
    private var completionView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(AppColors.primaryGreen)

            Text("Well Done!")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(.white)

            Text("You've completed \(viewModel.recipe.title)")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)

            // Rating
            VStack(spacing: 8) {
                Text("How was it?")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))

                HStack(spacing: 8) {
                    ForEach(1...5, id: \.self) { star in
                        Button {
                            // Rate recipe
                        } label: {
                            Image(systemName: "star.fill")
                                .font(.title2)
                                .foregroundStyle(.white.opacity(0.3))
                        }
                    }
                }
            }

            Spacer()

            VStack(spacing: 12) {
                Button {
                    Task {
                        await appState.markRecipeAsCooked(viewModel.recipe)
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
