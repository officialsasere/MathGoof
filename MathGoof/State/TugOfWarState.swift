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

@MainActor   // Every property mutation happens on the main thread — required
             // because RopePhysicsEngine is also @MainActor (CADisplayLink
             // callbacks must run on main), and because all @Published
             // property changes that drive SwiftUI must be on main.
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


    // MARK: - Computed helpers

    /// The live difficulty level mid-round — fluctuates as AdaptiveEngine
    /// adjusts based on performance. Shown in the top bar.
    var level: Int { adaptiveEngine.currentLevel }

    /// The stable stage the player is on. Increments by 1 after each win,
    /// stays the same after a loss. This is what drives the level progression
    /// — AdaptiveEngine starts each new stage at this level.
    @Published var currentLevel: Int = 1


    // MARK: - Init

    init(playerAvatar: Avatar) {
        self.playerAvatar = playerAvatar

        // CPU gets a random avatar that is different from the player's choice
        let others = Avatar.allAvatars.filter { $0.id != playerAvatar.id }
        self.cpuAvatar = others.randomElement() ?? Avatar.allAvatars[0]

        self.adaptiveEngine   = AdaptiveEngine(level: 1)
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


    // MARK: - Game Loop

    /// Start the physics engine. Call from the view's `.onAppear`.
    ///
    /// Why not call this in `init`?
    ///   RopePhysicsEngine is @MainActor. Calling `rope.start()` from `init`
    ///   would require `init` itself to be async or @MainActor, which makes
    ///   the @StateObject initialiser in the view more complicated. Deferring
    ///   to `.onAppear` is the standard SwiftUI pattern.
    func startGameLoop() {
        // Stop any existing display link first — critical when called from
        // startRound() so we don't have two display links running at once.
        rope.stop()
        syncDifficultyToRope()
        rope.start()
        adaptiveEngine.startTimer()
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
            // Scale pull strength by how fast the player answered.
            // Fast answers reward confident knowledge; slow answers still count
            // but give a smaller advantage.
            rope.correctPullStrength = playerPullStrength(for: responseTime)
            rope.applyCorrectAnswer()

            flashGreen      = true
            activeBattleCry = playerAvatar.battleCry

            if shouldLevelUp {
                adaptiveEngine.adjustDifficulty(levelChange: +1)
                syncDifficultyToRope()   // rope gets harder immediately
            }

        } else {
            // ── Wrong ────────────────────────────────────────────────────────
            // The physics engine applies its wrongAnswerPenalty (0.30 by default)
            // on top of the constant drift — so wrong answers feel costly.
            rope.applyWrongAnswer()

            flashRed        = true
            activeBattleCry = cpuAvatar.battleCry

            if shouldLevelDown {
                adaptiveEngine.adjustDifficulty(levelChange: -1)
                syncDifficultyToRope()   // rope eases off immediately
            }
        }

        // gameOver may have been triggered synchronously inside applyCorrectAnswer /
        // applyWrongAnswer via the Combine subscription — check before scheduling
        // the next question.
        if gameOver { return }

        // 0.9s pause: long enough for the kid to read the battle cry and see
        // the button colour, short enough to keep momentum.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard let self, !self.gameOver else { return }
            self.flashGreen       = false
            self.flashRed         = false
            self.activeBattleCry  = nil
            self.selectedAnswer   = nil
            self.currentChallenge = self.adaptiveEngine.generateChallenge()
            self.adaptiveEngine.startTimer()
        }
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


    // MARK: - Win Condition

    /// Called automatically by the Combine subscription every time rope.position
    /// changes. Stops the physics loop and flags game over.
    private func checkGameOver(position: Double) {
        guard !gameOver, abs(position) >= 1.0 else { return }
        gameOver = true
        rope.stop()   // stop the CADisplayLink — no more CPU cycles wasted
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
        gameOver          = false   // ← this dismisses the overlay

        // Start AdaptiveEngine at the stage level so question difficulty
        // and CPU drift both match where the player is in the game.
        adaptiveEngine   = AdaptiveEngine(level: level)
        currentChallenge = adaptiveEngine.generateChallenge()

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
