import SwiftUI

// MARK: - TugOfWarState.swift
// ─────────────────────────────────────────────────────────────────────────────
// Purpose: The ViewModel for the Tug of War game. Owns all game state and
//   wires together the AdaptiveEngine (questions + difficulty) with the
//   RopePhysicsEngine (the real-time rope movement loop).
//
// Why RopePhysicsEngine instead of a Timer?
//   RopePhysicsEngine uses CADisplayLink, which is tied directly to the
//   screen's refresh cycle. This gives two advantages:
//
//   1. FRAME-RATE ACCURACY: It calculates a `deltaTime` (how many real seconds
//      passed since the last frame) and multiplies all movement by it. This
//      means the rope moves at the same perceived speed on a 60fps iPhone SE
//      and a 120fps ProMotion iPad. A plain Timer fires at a fixed interval
//      regardless of the actual frame rate, so on a ProMotion device it would
//      feel twice as slow.
//
//   2. VSYNC: The update fires at exactly the right moment before each frame
//      is drawn, so there is zero "stutter" — the knot position is always
//      fresh for every frame.
//
// Ownership model:
//   TugOfWarState OWNS RopePhysicsEngine (stored as a regular property).
//   TugOfWarState subscribes to rope's @Published properties via Combine so
//   changes propagate through to SwiftUI automatically.
//
// MVVM roles:
//   Model       = MathChallenge, Avatar         (Models.swift)
//   Physics     = RopePhysicsEngine             (RopePhysicsEngine.swift)
//   ViewModel   = TugOfWarState                 (this file)
//   View        = TugOfWarView                  (TugOfWarView.swift)
// ─────────────────────────────────────────────────────────────────────────────

import Combine

@MainActor
class TugOfWarState: ObservableObject {

    // MARK: - Published game state (SwiftUI re-renders when these change)

    @Published var playerAvatar: Avatar
    @Published var cpuAvatar: Avatar

    /// The current math question being shown.
    @Published var currentChallenge: MathChallenge

    /// Which answer the player tapped this round. Nil = waiting for input.
    @Published var selectedAnswer: Int? = nil

    /// Whether the last tapped answer was correct. Used to colour the button.
    @Published var lastAnswerCorrect: Bool = false

    /// Becomes true when the rope reaches ±1.0. Locks the UI and shows the
    /// game-over overlay.
    @Published var gameOver: Bool = false

    /// Brief flash states — animate the avatar emoji on the rope to give
    /// instant visual feedback when a pull happens.
    @Published var flashGreen: Bool = false
    @Published var flashRed:   Bool = false

    /// The battle cry flashed on screen after each pull event.
    @Published var activeBattleCry: String? = nil

    // MARK: - Sprint 1 features

    /// Feature 9 — Streak counter.
    /// Counts consecutive correct answers in the current round.
    /// Resets to 0 on any wrong answer or when a new round starts.
    /// The view shows a fire badge "🔥 ×3" when this is ≥ 2.
    @Published var correctStreak: Int = 0

    /// Feature 10 — Sound toggle.
    /// When false, TugOfWarView passes this flag to TugAudioManager and all
    /// sounds/haptics are skipped. Persisted in UserDefaults so the
    /// setting survives app restarts.
    @Published var isSoundEnabled: Bool = UserDefaults.standard.object(forKey: "tugSoundEnabled") as? Bool ?? true

    /// Feature 4 — CPU personality state.
    /// Changes based on who is currently winning the rope.
    /// The view uses this to show a different emoji expression on the CPU avatar.
    enum CPUMood { case neutral, nervous, cocky, desperate }
    @Published var cpuMood: CPUMood = .neutral

    // MARK: - Sprint 2 features

    /// Feature 1 — Countdown timer.
    /// Fraction remaining: 1.0 = full time, 0.0 = time up.
    /// Driven by a Timer that fires every 0.05s.
    @Published var timerFraction: Double = 1.0

    /// Feature 2 — Stars earned this round (1–3). Set at win time.
    /// 0 means the round hasn't been won yet.
    @Published var starsEarned: Int = 0

    /// Feature 3 — Power-up availability.
    /// True when the player has earned a Super Pull and hasn't used it yet.
    @Published var powerUpReady: Bool = false

    /// Feature 3 — Visual flash when the power-up fires.
    @Published var powerUpFlash: Bool = false

    /// Feature 6 — Reference to the persistent player profile.
    /// Weak so TugOfWarState doesn't keep the profile alive if the app root
    /// releases it (though in practice it lives for the whole app lifetime).
    weak var profile: PlayerProfile?


    // MARK: - Physics engine (the rope's real-time loop)

    /// The RopePhysicsEngine drives the rope at 60fps via CADisplayLink.
    /// We expose it as `internal` (no access modifier needed) so TugOfWarView
    /// can read `rope.position` and `rope.isNearEdge` directly — this avoids
    /// duplicating those @Published values here and keeps one source of truth.
    let rope = RopePhysicsEngine()

    /// Combine subscriptions. We hold onto these so they stay alive for the
    /// lifetime of TugOfWarState. If we didn't store them, Combine would
    /// cancel the subscriptions immediately after creation.
    private var cancellables = Set<AnyCancellable>()


    // MARK: - Private state

    private var adaptiveEngine: AdaptiveEngine

    /// Feature 1 — the repeating timer that drains timerFraction each tick.
    private var questionTimer: Timer?

    /// Feature 1 — total seconds allowed per question, set per level.
    private var questionTimeLimit: Double = 10.0

    /// Feature 1 — seconds elapsed since the current question appeared.
    private var questionTimeElapsed: Double = 0.0

    /// Feature 3 — counts correct answers toward the next power-up.
    /// Resets to 0 each time a power-up is awarded.
    private var answersTowardPowerUp: Int = 0

    /// Feature 6 — tracks correct answers this round for profile recording.
    private var roundCorrectAnswers: Int = 0

    /// Feature 6 — tracks the fastest answer time this round (ms).
    private var roundFastestMs: Int = 0

    /// Feature 7 — Daily challenge question queue.
    /// When non-nil, generateChallenge() is NOT called — questions are
    /// consumed from this list in order. This is how we inject the seeded
    /// daily questions without changing any other game logic.
    private var dailyQuestions: [MathChallenge]? = nil
    private var dailyQuestionIndex: Int = 0


    // MARK: - Computed helpers

    /// The live difficulty level mid-round — fluctuates as AdaptiveEngine
    /// adjusts based on performance. Shown in the top bar.
    var level: Int { adaptiveEngine.currentLevel }

    /// The stable stage the player is on. Increments by 1 after each win,
    /// stays the same after a loss. This is what drives the level progression
    /// — AdaptiveEngine starts each new stage at this level.
    @Published var currentLevel: Int = 1


    // MARK: - Init

    /// Standard init for VS-CPU and level-map play.
    init(playerAvatar: Avatar, startLevel: Int = 1, profile: PlayerProfile? = nil) {
        self.playerAvatar = playerAvatar
        self.profile      = profile
        self.currentLevel = startLevel   // Feature 5: start at the chosen map level

        let others = Avatar.allAvatars.filter { $0.id != playerAvatar.id }
        self.cpuAvatar = others.randomElement() ?? Avatar.allAvatars[0]

        self.adaptiveEngine   = AdaptiveEngine(level: startLevel)
        self.currentChallenge = adaptiveEngine.generateChallenge()

        // Subscribe to the rope's position so we can detect game-over
        // without polling. Every time `rope.position` changes, this closure
        // runs and checks whether either player has won.
        //
        // `.receive(on: RunLoop.main)` ensures the closure fires on the main
        // thread even if Combine delivers it on a background thread.
        rope.$position
            .receive(on: RunLoop.main)
            .sink { [weak self] position in
                self?.checkGameOver(position: position)
            }
            .store(in: &cancellables)
    }

    /// Daily challenge init — same as standard but injects pre-seeded questions.
    /// The rope, CPU, timer, and all other mechanics work identically.
    convenience init(playerAvatar: Avatar,
                     dailyQuestions: [MathChallenge],
                     profile: PlayerProfile? = nil) {
        self.init(playerAvatar: playerAvatar, startLevel: 5, profile: profile)
        self.dailyQuestions = dailyQuestions
        self.dailyQuestionIndex = 0
        // Replace the first question with the first daily question
        self.currentChallenge = dailyQuestions[0]
    }


    // MARK: - Game Loop

    /// Start the physics engine. Call from the view's `.onAppear`.
    ///
    /// Why not call this in `init`?
    ///   RopePhysicsEngine is @MainActor. Calling `rope.start()` from `init`
    ///   would require `init` itself to be async or @MainActor, which makes
    ///   the @StateObject initialiser in the view more complicated. Deferring
    ///   to `.onAppear` is the standard SwiftUI pattern.
    func startGameLoop() {
        rope.stop()
        syncDifficultyToRope()
        rope.start()
        adaptiveEngine.startTimer()
        startQuestionTimer()   // Feature 1
    }

    // MARK: - Feature 1: Question Timer

    /// Starts the per-question countdown. The time limit shrinks with level:
    ///   Level 1 = 12s, Level 5 = 8s, Level 10 = 5s.
    /// When it hits zero the CPU gets a free pull and a new question loads.
    private func startQuestionTimer() {
        questionTimer?.invalidate()
        questionTimeElapsed = 0.0
        // Time limit decreases with level — higher levels demand faster answers
        questionTimeLimit = max(5.0, 12.0 - Double(adaptiveEngine.currentLevel - 1) * 0.75)
        timerFraction = 1.0

        questionTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            // Timer callbacks are nonisolated — we must explicitly hop to
            // MainActor because tickQuestionTimer() mutates @Published state.
            Task { @MainActor [weak self] in
                self?.tickQuestionTimer()
            }
        }
    }

    private func tickQuestionTimer() {
        guard !gameOver, selectedAnswer == nil else { return }
        questionTimeElapsed += 0.05
        timerFraction = max(0.0, 1.0 - (questionTimeElapsed / questionTimeLimit))

        if timerFraction <= 0 {
            // Time's up — CPU gets a free pull, load next question
            questionTimer?.invalidate()
            rope.applyWrongAnswer()   // CPU free pull
            correctStreak = 0         // streak breaks on timeout
            answersTowardPowerUp = 0
            updateCPUMood()

            // Brief pause then next question
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self, !self.gameOver else { return }
                self.currentChallenge = self.nextQuestion()
                self.adaptiveEngine.startTimer()
                self.startQuestionTimer()
            }
        }
    }

    private func stopQuestionTimer() {
        questionTimer?.invalidate()
        questionTimer = nil
        timerFraction = 1.0
    }

    /// Keeps the rope's levelDriftMultiplier in sync with the adaptive engine.
    /// Called after every difficulty adjustment so the rope immediately
    /// feels harder or easier.
    ///
    /// Formula: multiplier = 1.0 + (level - 1) × 0.20
    ///
    ///   Level 1  → 1.00×  drift = 0.06/sec  (~16s to drain)
    ///   Level 3  → 1.40×  drift = 0.084/sec (~12s to drain)
    ///   Level 5  → 1.80×  drift = 0.108/sec (~9s to drain)
    ///   Level 7  → 2.20×  drift = 0.132/sec (~8s to drain)
    ///   Level 10 → 2.80×  drift = 0.168/sec (~6s to drain)
    ///
    /// The step size (0.20) is intentionally modest so each level feels
    /// like a noticeable increase without a sudden difficulty spike.
    private func syncDifficultyToRope() {
        rope.levelDriftMultiplier = 1.0 + Double(adaptiveEngine.currentLevel - 1) * 0.20
    }

    /// Feature 10 — toggles sound on/off and persists the choice.
    func toggleSound() {
        isSoundEnabled.toggle()
        UserDefaults.standard.set(isSoundEnabled, forKey: "tugSoundEnabled")
    }


    // MARK: - Player Answer

    /// Called when the player taps an answer button.
    ///
    /// Flow:
    ///   1. Stop the response-time clock.
    ///   2. Tell the physics engine to apply pull or penalty instantly.
    ///   3. Update metrics and adjust difficulty if needed.
    ///   4. Flash the avatar + show battle cry for visual feedback.
    ///   5. After 0.9s, clear feedback state and load the next question.
    func answer(_ tappedAnswer: Int) {
        guard selectedAnswer == nil, !gameOver else { return }

        // Capture response time before anything else changes the clock
        let responseTime = adaptiveEngine.stopTimer()

        selectedAnswer    = tappedAnswer
        lastAnswerCorrect = (tappedAnswer == currentChallenge.correctAnswer)

        let (shouldLevelUp, shouldLevelDown) = adaptiveEngine.recordAnswer(isCorrect: lastAnswerCorrect)

        if lastAnswerCorrect {
            // ── Correct ───────────────────────────────────────────────────────
            rope.correctPullStrength = playerPullStrength(for: responseTime)
            rope.applyCorrectAnswer()

            // Feature 9: streak
            correctStreak += 1
            activeBattleCry = correctStreak >= 3
                ? "🔥 ON FIRE! \(playerAvatar.battleCry)"
                : playerAvatar.battleCry
            flashGreen = true

            // Feature 3: count toward power-up (every 3 correct in a row)
            answersTowardPowerUp += 1
            if answersTowardPowerUp >= 3, !powerUpReady {
                powerUpReady = true
                answersTowardPowerUp = 0
            }

            // Feature 6: track correct answers and fastest time for profile
            roundCorrectAnswers += 1
            let ms = Int(responseTime * 1000)
            if roundFastestMs == 0 || ms < roundFastestMs { roundFastestMs = ms }

            if shouldLevelUp {
                adaptiveEngine.adjustDifficulty(levelChange: +1)
                syncDifficultyToRope()
            }

        } else {
            // ── Wrong ────────────────────────────────────────────────────────
            rope.applyWrongAnswer()
            correctStreak = 0
            answersTowardPowerUp = 0   // Feature 3: reset on wrong answer
            activeBattleCry = cpuAvatar.battleCry
            flashRed = true

            if shouldLevelDown {
                adaptiveEngine.adjustDifficulty(levelChange: -1)
                syncDifficultyToRope()
            }
        }

        updateCPUMood()

        // gameOver may have been triggered synchronously inside applyCorrectAnswer /
        // applyWrongAnswer via the Combine subscription — check before scheduling
        // the next question.
        if gameOver { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard let self, !self.gameOver else { return }
            self.flashGreen       = false
            self.flashRed         = false
            self.activeBattleCry  = nil
            self.selectedAnswer   = nil
            self.currentChallenge = self.nextQuestion()
            self.adaptiveEngine.startTimer()
            self.startQuestionTimer()   // Feature 1: restart countdown
        }
    }


    // MARK: - Question Source

    /// Returns the next question from the daily queue (if set) or from the
    /// adaptive engine. This single method is the only place question
    /// generation happens — all callers use it instead of calling
    /// adaptiveEngine.generateChallenge() directly.
    private func nextQuestion() -> MathChallenge {
        if var queue = dailyQuestions {
            dailyQuestionIndex += 1
            if dailyQuestionIndex < queue.count {
                return queue[dailyQuestionIndex]
            }
            // Queue exhausted — fall through to adaptive engine
            dailyQuestions = nil
        }
        return adaptiveEngine.generateChallenge()
    }


    // MARK: - Pull Strength

    /// Maps response time to a pull magnitude set on the physics engine.
    ///
    /// Pull strengths are generous so correct answers always feel impactful —
    /// the child should visibly see the knot move toward their side.
    ///
    ///   < 2.0s → 0.50  (fast — big rewarding pull)
    ///   < 4.0s → 0.38  (medium — clear progress)
    ///   ≥ 4.0s → 0.25  (slow but correct — still meaningful)
    ///
    /// At level 1, even a slow correct answer (0.25) cancels ~4 seconds of
    /// CPU drift (0.06/sec), so the player always feels in control.
    private func playerPullStrength(for responseTime: TimeInterval) -> Double {
        if responseTime < 2.0 { return 0.50 }
        if responseTime < 4.0 { return 0.38 }
        return 0.25
    }

    // MARK: - Feature 3: Power-Up

    /// Called when the player taps the Super Pull button.
    /// Gives a massive one-time rope yank (0.70 — more than a correct answer).
    /// The button is only shown when powerUpReady == true.
    func activatePowerUp() {
        guard powerUpReady, !gameOver else { return }
        powerUpReady  = false
        powerUpFlash  = true

        rope.correctPullStrength = 0.70
        rope.applyCorrectAnswer()
        updateCPUMood()

        // Flash fades after 0.4s
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.powerUpFlash = false
        }
    }


    // MARK: - CPU Mood (Feature 4)

    /// Updates the CPU's displayed emotion based on who is winning.
    ///
    ///   rope > +0.4  → CPU is nervous (player is winning)
    ///   rope > +0.7  → CPU is desperate (player is very close to winning)
    ///   rope < -0.4  → CPU is cocky (CPU is winning)
    ///   otherwise    → neutral
    ///
    /// Called after every answer so the CPU reacts in real time.
    private func updateCPUMood() {
        let p = rope.position
        if p > 0.7 {
            cpuMood = .desperate
        } else if p > 0.4 {
            cpuMood = .nervous
        } else if p < -0.4 {
            cpuMood = .cocky
        } else {
            cpuMood = .neutral
        }
    }

    // MARK: - Win Condition

    /// Called automatically by the Combine subscription every time rope.position
    /// changes. Stops the physics loop, calculates stars, saves profile.
    private func checkGameOver(position: Double) {
        guard !gameOver, abs(position) >= 1.0 else { return }
        gameOver = true
        rope.stop()
        stopQuestionTimer()   // Feature 1: stop countdown

        // Feature 2: calculate stars only on a player win
        if position >= 1.0 {
            starsEarned = LevelResult.stars(for: Double(correctStreak) / 5.0 + 0.5)
            // Better heuristic: base stars on how dominant the win was.
            // We use the rope's peak (always 1.0 at win), so we instead
            // derive stars from streak and speed together:
            //   streak >= 4 → 3 stars, streak >= 2 → 2 stars, else 1 star
            starsEarned = correctStreak >= 4 ? 3 : correctStreak >= 2 ? 2 : 1

            // Feature 6: record win in player profile
            profile?.recordWin(
                level:           currentLevel,
                ropePosition:    position,
                correctAnswers:  roundCorrectAnswers,
                fastestAnswerMs: roundFastestMs
            )
        } else {
            starsEarned = 0
        }
    }


    // MARK: - Level Progression

    /// Called when the player WINS. Advances to the next stage level.
    /// The AdaptiveEngine starts fresh at the new level so questions and
    /// CPU drift both get harder.
    func nextLevel() {
        currentLevel = min(currentLevel + 1, 10)
        startRound(at: currentLevel)
    }

    /// Called when the player LOSES. Resets the rope but keeps the same
    /// level so they can try again without losing their progress.
    func retryLevel() {
        startRound(at: currentLevel)
    }

    /// Shared reset logic. Starts a clean round at the given stage level.
    ///
    /// Order matters:
    ///   1. Stop the rope first — prevents the CADisplayLink from publishing
    ///      position changes while we're resetting state.
    ///   2. Reset position to 0.0 — so the Combine sink (checkGameOver) cannot
    ///      immediately re-fire and set gameOver = true again the moment the
    ///      new display link starts.
    ///   3. Set gameOver = false — now safe because the rope is stopped and
    ///      position is clean.
    ///   4. Start the game loop — begins fresh from centre.
    private func startRound(at level: Int) {
        rope.stop()       // 1. halt display link immediately
        rope.reset()      // 2. position = 0.0 before gameOver flips

        // 3. clear all UI state — gameOver last so the overlay dismisses
        //    only after position is already clean
        selectedAnswer    = nil
        lastAnswerCorrect = false
        flashGreen        = false
        flashRed          = false
        activeBattleCry   = nil
        correctStreak        = 0
        cpuMood              = .neutral
        // Sprint 2 resets
        starsEarned          = 0
        powerUpReady         = false
        powerUpFlash         = false
        answersTowardPowerUp = 0
        roundCorrectAnswers  = 0
        roundFastestMs       = 0
        stopQuestionTimer()
        gameOver             = false

        // Start AdaptiveEngine at the stage level so question difficulty
        // and CPU drift both match where the player is in the game.
        adaptiveEngine      = AdaptiveEngine(level: level)
        dailyQuestionIndex  = 0   // reset daily queue if retrying
        currentChallenge    = nextQuestion()

        startGameLoop()   // 4. start fresh
    }


    // MARK: - Cleanup

    deinit {
        // Problem: even on a @MainActor class, Swift treats `deinit` as
        // nonisolated in Swift 5.9 and earlier. Calling rope.stop() directly
        // therefore produces:
        //   "Call to main actor-isolated instance method 'stop()' in a
        //    synchronous nonisolated context"
        //
        // Fix: `MainActor.assumeIsolated` tells the runtime "I promise this
        // code is already running on the main thread — treat it as
        // main-actor-isolated for this closure". It is safe here because
        // TugOfWarState is only ever created and destroyed from SwiftUI views,
        // which always run on the main thread.
        //
        // Note: In Swift 5.10+ @MainActor deinit works without this wrapper,
        // but assumeIsolated is harmless to keep for backwards compatibility.
        MainActor.assumeIsolated {
            rope.stop()
        }
    }
}
