import SwiftUI
import AVFoundation
import Combine

@Observable
@MainActor
final class MultiCookModeViewModel {
    var currentBlockIndex = 0
    var timerSeconds: Int = 0
    var isTimerRunning = false
    var isPaused = false
    var showCompletionScreen = false
    var voiceAuthorizationDenied = false

    // Conversational voice mode (Realtime API)
    var isConversationActive = false
    var isPreparing = false
    var conversationTranscript = ""
    var isModelSpeaking = false
    var isUserSpeaking = false
    var conversationStatus = ""
    var conversationError: String?
    var isMuted = false

    // Passive timer state
    var runningTimers: [RunningPassiveTimer] = []
    var finishedTimerName: String?
    var showTimerFinishedAlert = false

    /// Flags for session lifecycle
    var isEndingSession = false
    var didContinueInBackground = false

    let recipes: [Recipe]
    let blocks: [MultiRecipeScheduler.ScheduledBlock]
    let realtimeService: any RealtimeServiceProtocol
    let preferenceStore: CookModePreferenceStoreProtocol
    let queueID: UUID?
    let queueStageID: UUID?

    /// Stable identifier persisted across resume cycles.
    let sessionId: UUID

    private var wasEverConnected = false

    /// Date-based timer tracking
    private var timerStartedAt: Date?
    private var timerDuration: TimeInterval = 0
    private var timerPausedRemaining: TimeInterval = 0
    private var timerCancellable: AnyCancellable?

    /// 1-second tick for passive timer countdowns
    private var passiveTickCancellable: AnyCancellable?

    init(
        recipes: [Recipe],
        blocks: [MultiRecipeScheduler.ScheduledBlock],
        realtimeService: any RealtimeServiceProtocol,
        preferenceStore: CookModePreferenceStoreProtocol? = nil,
        queueID: UUID? = nil,
        queueStageID: UUID? = nil,
        sessionId: UUID = UUID(),
        resumeAtBlock: Int = 0
    ) {
        self.recipes = recipes
        self.blocks = blocks
        self.realtimeService = realtimeService
        self.preferenceStore = preferenceStore ?? UserDefaultsCookModePreferenceStore()
        self.queueID = queueID
        self.queueStageID = queueStageID
        self.sessionId = sessionId
        self.currentBlockIndex = resumeAtBlock
        self.isMuted = self.preferenceStore.isMuted
        setupRealtimeCallbacks()
        startPassiveTimerTick()
        // Persist immediately so session is resumable from the start
        persistSession()
    }

    var currentBlock: MultiRecipeScheduler.ScheduledBlock? {
        guard currentBlockIndex < blocks.count else { return nil }
        return blocks[currentBlockIndex]
    }

    var progress: Double {
        guard !blocks.isEmpty else { return 0 }
        return Double(currentBlockIndex + 1) / Double(blocks.count)
    }

    var isFirstBlock: Bool { currentBlockIndex == 0 }
    var isLastBlock: Bool { currentBlockIndex >= blocks.count - 1 }

    var timerDisplay: String {
        let minutes = timerSeconds / 60
        let seconds = timerSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    // MARK: - Navigation

    func nextBlock() {
        guard !isLastBlock else {
            stopTimer()
            showCompletionScreen = true
            stopConversation()
            clearSession()
            return
        }
        maybeStartPassiveTimer()
        stopTimer()
        currentBlockIndex += 1
        notifyBlockChanged()
        persistSession()
    }

    func previousBlock() {
        guard !isFirstBlock else { return }
        stopTimer()
        currentBlockIndex -= 1
        // Remove passive timers started from blocks after new position
        let validBlockIDs = Set(blocks.prefix(currentBlockIndex).map(\.id))
        runningTimers.removeAll { !validBlockIDs.contains($0.blockId) }
        notifyBlockChanged()
        persistSession()
    }

    func goToBlock(_ index: Int) {
        guard index >= 0 && index < blocks.count else { return }
        stopTimer()
        currentBlockIndex = index
        notifyBlockChanged()
        persistSession()
    }

    /// Tell the Realtime API model about the new block so it reads it aloud.
    private func notifyBlockChanged() {
        guard !isMuted, isConversationActive, let block = currentBlock else { return }
        let msg = "The user moved to block \(currentBlockIndex + 1) of \(blocks.count): \(block.displayInstruction). Read this instruction aloud for them, briefly."
        realtimeService.sendUserMessage(msg)
    }

    /// If the current block is passive, start a background timer for it before advancing.
    private func maybeStartPassiveTimer() {
        guard let block = currentBlock, block.type == .passive, block.totalDurationSeconds > 0 else { return }
        let label = block.tasks.first.map { task -> String in
            let name = task.recipeName ?? "Timer"
            let verb = task.action.verb
            return "\(verb) (\(name))"
        } ?? "Passive"
        let rt = RunningPassiveTimer(
            blockId: block.id,
            label: label,
            totalSeconds: block.totalDurationSeconds,
            startedAt: Date()
        )
        runningTimers.append(rt)
    }

    // MARK: - Mute

    func toggleMute() {
        isMuted.toggle()
        preferenceStore.isMuted = isMuted
        if isMuted {
            realtimeService.stopCapture()
            realtimeService.silenceAI()
        } else {
            realtimeService.startCapture()
        }
    }

    // MARK: - Conversational Voice (OpenAI Realtime API)

    func startConversation() {
        Task {
            let micAuthorized = await CookModeViewModel.requestMicrophoneAuthorization()
            guard micAuthorized else {
                voiceAuthorizationDenied = true
                return
            }

            isConversationActive = true
            isPreparing = true
            voiceAuthorizationDenied = false
            conversationStatus = "Setting up audio…"

            await realtimeService.prepareAudio()

            guard realtimeService.isAudioReady else {
                isPreparing = false
                isConversationActive = false
                conversationError = "Audio engine failed to start. Please check your device's audio settings."
                return
            }

            let instructions = buildConversationInstructions()
            let tools = buildConversationTools()
            realtimeService.connect(withInstructions: instructions, tools: tools)
            isPreparing = false
            persistSession()

            if isMuted {
                realtimeService.stopCapture()
                realtimeService.silenceAI()
            } else {
                realtimeService.startCapture()

                let greeting = "The user just started a multi-recipe cook session with \(recipes.count) recipes: "
                    + recipes.map(\.title).joined(separator: ", ") + ". "
                    + "Greet them warmly and briefly read the first block instruction: "
                    + "\(currentBlock?.displayInstruction ?? ""). Keep it concise."
                realtimeService.sendUserMessage(greeting)
            }
        }
    }

    func stopConversation() {
        isConversationActive = false
        wasEverConnected = false
        realtimeService.disconnect()
        conversationTranscript = ""
        conversationStatus = ""
        conversationError = nil
        isModelSpeaking = false
        isUserSpeaking = false
    }

    private func setupRealtimeCallbacks() {
        realtimeService.onFunctionCall = { [weak self] name, args in
            Task { @MainActor in
                self?.handleRealtimeFunctionCall(name: name, args: args)
            }
        }
    }

    /// Syncs observable state from RealtimeService — called by the view's timer.
    func syncRealtimeState() {
        guard isConversationActive else { return }
        conversationTranscript = realtimeService.transcript
        isModelSpeaking = realtimeService.isModelSpeaking
        isUserSpeaking = realtimeService.isUserSpeaking
        conversationStatus = realtimeService.statusMessage
        conversationError = realtimeService.errorMessage

        if realtimeService.isConnected {
            wasEverConnected = true
        }

        if !isPreparing && wasEverConnected && !realtimeService.isConnected && isConversationActive {
            isConversationActive = false
        }
    }

    func handleRealtimeFunctionCall(name: String, args: [String: Any]) {
        switch name {
        case "next_block":
            guard !isLastBlock else {
                stopTimer()
                stopConversation()
                clearSession()
                showCompletionScreen = true
                return
            }
            maybeStartPassiveTimer()
            stopTimer()
            currentBlockIndex += 1
            persistSession()
        case "previous_block":
            guard !isFirstBlock else { return }
            stopTimer()
            currentBlockIndex -= 1
            persistSession()
        case "go_to_block":
            if let block = args["block_number"] as? Int {
                let index = block - 1
                guard index >= 0 && index < blocks.count else { return }
                stopTimer()
                currentBlockIndex = index
                persistSession()
            }
        case "start_timer":
            if let minutes = args["minutes"] as? Int {
                startTimerWithMinutes(minutes)
            }
        case "pause_timer":
            pauseTimer()
        case "stop_timer":
            stopTimer()
        case "finish_cooking":
            endSession()
            showCompletionScreen = true
        default:
            break
        }
    }

    func buildConversationInstructions() -> String {
        let blocksText = blocks.enumerated().map { idx, block in
            var s = "Block \(idx + 1)"
            if block.type == .passive { s += " [PASSIVE — timer-based wait]" }
            s += ": \(block.displayInstruction)"
            s += " (recipes: \(block.recipeNames.joined(separator: ", ")), ~\(block.totalDurationSeconds / 60) min)"
            return s
        }.joined(separator: "\n")

        let recipeList = recipes.map(\.title).joined(separator: ", ")

        return """
        You are an interactive cooking assistant helping the user cook \(recipes.count) recipes \
        simultaneously: \(recipeList). Be warm, encouraging, and concise.

        The LLM scheduler has organized the cooking into an interleaved timeline of blocks. \
        Each block contains a natural-language instruction that may merge tasks from multiple \
        recipes for efficiency.

        BLOCKS:
        \(blocksText)

        The user is currently on block \(currentBlockIndex + 1) of \(blocks.count).

        BEHAVIOR:
        - Read block instructions aloud naturally. The instructions are already written in \
        natural language — paraphrase slightly for a conversational feel.
        - When the user asks cooking questions, answer helpfully using your cooking knowledge.
        - Use the provided function tools for navigation: call next_block, previous_block, \
        go_to_block, start_timer, etc. when the user asks.
        - If the user asks for a specific numbered block, call go_to_block directly.
        - After calling a navigation function, briefly acknowledge it then read the new block.
        - Keep responses SHORT — 1-3 sentences normally.
        - If the user says they're done or finished, call finish_cooking.
        - You can be interrupted — that's fine, just respond to the new input.
        - IMPORTANT: If the user says "stop", "pause", "wait", "hold on", or "quiet" — \
        stop talking immediately. Say "OK" or "Sure, I'll wait" and be silent until they speak.
        - NEVER move to the next block unless the user explicitly says "next", "next step", \
        "move on", "continue", "I'm ready", or similar.
        - CRITICAL: You MUST call the next_block tool to advance. NEVER just verbally \
        describe the next block without calling the tool first.
        - For PASSIVE blocks (timer-based waits like simmering or baking), let the user know \
        a timer will start automatically and they can move on while it runs.
        - NOISE REJECTION: Kitchen sounds sometimes produce garbage transcriptions. If the \
        input clearly isn't intentional speech, stay silent.
        - OFF-TOPIC REJECTION: If the user asks about something unrelated to cooking, food, \
        or these recipes (e.g. programming, homework, math problems), politely decline and \
        remind them you're here to help with cooking. Say something like: "I'm your cooking \
        assistant — I can only help with these recipes and food-related questions!"
        - Always speak in English.
        """
    }

    func buildConversationTools() -> [[String: Any]] {
        return [
            [
                "type": "function",
                "name": "next_block",
                "description": "Move to the next cooking block",
                "parameters": [
                    "type": "object",
                    "properties": [:] as [String: Any],
                    "required": [] as [String]
                ]
            ],
            [
                "type": "function",
                "name": "previous_block",
                "description": "Go back to the previous cooking block",
                "parameters": [
                    "type": "object",
                    "properties": [:] as [String: Any],
                    "required": [] as [String]
                ]
            ],
            [
                "type": "function",
                "name": "go_to_block",
                "description": "Jump to a specific block number",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "block_number": [
                            "type": "integer",
                            "description": "The block number to jump to (1-based)"
                        ]
                    ],
                    "required": ["block_number"]
                ]
            ],
            [
                "type": "function",
                "name": "start_timer",
                "description": "Start a timer for the specified number of minutes",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "minutes": [
                            "type": "integer",
                            "description": "Number of minutes for the timer"
                        ]
                    ],
                    "required": ["minutes"]
                ]
            ],
            [
                "type": "function",
                "name": "pause_timer",
                "description": "Pause or resume the current timer",
                "parameters": [
                    "type": "object",
                    "properties": [:] as [String: Any],
                    "required": [] as [String]
                ]
            ],
            [
                "type": "function",
                "name": "stop_timer",
                "description": "Stop and reset the current timer",
                "parameters": [
                    "type": "object",
                    "properties": [:] as [String: Any],
                    "required": [] as [String]
                ]
            ],
            [
                "type": "function",
                "name": "finish_cooking",
                "description": "End the cooking session when the user says they are done.",
                "parameters": [
                    "type": "object",
                    "properties": [:] as [String: Any],
                    "required": [] as [String]
                ]
            ]
        ]
    }

    // MARK: - Timer (Date-based)

    private func startTimerWithMinutes(_ minutes: Int) {
        let duration = TimeInterval(minutes * 60)
        timerDuration = duration
        timerStartedAt = Date()
        timerPausedRemaining = 0
        timerSeconds = minutes * 60
        isTimerRunning = true
        isPaused = false
        startTimerTick()
    }

    private func startTimerTick() {
        timerCancellable?.cancel()
        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                self.recalculateTimerSeconds()
                if self.timerSeconds <= 0 {
                    self.timerComplete()
                }
            }
    }

    private func recalculateTimerSeconds() {
        guard let startedAt = timerStartedAt else { return }
        let elapsed = Date().timeIntervalSince(startedAt)
        let remaining = max(0, timerDuration - elapsed)
        timerSeconds = Int(remaining.rounded(.up))
    }

    func stopTimer() {
        isTimerRunning = false
        isPaused = false
        timerStartedAt = nil
        timerDuration = 0
        timerPausedRemaining = 0
        timerCancellable?.cancel()
        timerCancellable = nil
    }

    func pauseTimer() {
        isPaused.toggle()
        if isPaused {
            recalculateTimerSeconds()
            timerPausedRemaining = TimeInterval(timerSeconds)
            timerCancellable?.cancel()
        } else {
            timerDuration = timerPausedRemaining
            timerStartedAt = Date()
            startTimerTick()
        }
    }

    private func timerComplete() {
        stopTimer()
        if isConversationActive {
            realtimeService.sendUserMessage(
                "The timer just finished! Let the user know and ask if they're ready for the next block."
            )
        }
    }

    // MARK: - Passive Timer Tick

    private func startPassiveTimerTick() {
        passiveTickCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tickPassiveTimers()
            }
    }

    private func tickPassiveTimers() {
        var finished: [RunningPassiveTimer] = []

        for i in runningTimers.indices {
            let elapsed = Date().timeIntervalSince(runningTimers[i].startedAt)
            let remaining = max(0, runningTimers[i].totalSeconds - Int(elapsed))
            runningTimers[i].remainingSeconds = remaining
            if remaining == 0 {
                finished.append(runningTimers[i])
            }
        }

        if let first = finished.first {
            runningTimers.removeAll { $0.remainingSeconds == 0 }
            finishedTimerName = first.label

            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            showTimerFinishedAlert = true

            // Notify voice AI about finished timer
            if isConversationActive {
                realtimeService.sendUserMessage(
                    "\(first.label) timer just finished! Let the user know."
                )
            }
        }
    }

    func cleanup() {
        passiveTickCancellable?.cancel()
        timerCancellable?.cancel()
        realtimeService.onFunctionCall = nil
        stopConversation()
    }

    /// Continue cooking in background — keeps session persisted, stops voice.
    func continueInBackground() {
        didContinueInBackground = true
        stopConversation()
        persistSession()
    }

    /// Resume from background — reconnect voice.
    func resumeFromBackground() {
        didContinueInBackground = false
        startConversation()
    }

    /// End session permanently — clears persisted state.
    func endSession() {
        isEndingSession = true
        stopTimer()
        stopConversation()
        clearSession()
    }

    // MARK: - Session Persistence

    func persistSession() {
        var session = MultiCookSession(
            id: sessionId,
            recipeIDs: recipes.map(\.id),
            recipeNames: recipes.map(\.title),
            blocks: blocks,
            currentBlockIndex: currentBlockIndex,
            startedAt: Date(),
            lastUpdatedAt: Date(),
            queueID: queueID,
            queueStageID: queueStageID
        )
        // Preserve original startedAt if resuming
        if let existing = MultiCookSession.load(id: sessionId) {
            session = MultiCookSession(
                id: sessionId,
                recipeIDs: recipes.map(\.id),
                recipeNames: recipes.map(\.title),
                blocks: blocks,
                currentBlockIndex: currentBlockIndex,
                startedAt: existing.startedAt,
                lastUpdatedAt: Date(),
                queueID: queueID,
                queueStageID: queueStageID
            )
        }
        session.save()
    }

    func clearSession() {
        MultiCookSession.clear(id: sessionId)
    }
}
