import Foundation

// MARK: - AdaptiveEngine.swift
// ─────────────────────────────────────────────────────────────────────────────
// Purpose: Generates math questions at the right difficulty AND decides when
//   to make the game harder or easier based on the player's performance.
//
// Usage sequence each question:
//   1. generateChallenge()   → get the question
//   2. startTimer()          → call when question appears on screen
//   3. stopTimer()           → call when player taps an answer (returns seconds)
//   4. recordAnswer(isCorrect:) → update metrics
//   5. adjustDifficulty(levelChange:) → call if flags from step 4 say to
// ─────────────────────────────────────────────────────────────────────────────

class AdaptiveEngine {

    private var metrics = PerformanceMetrics()
    private var currentDifficulty: DifficultyLevel

    /// Timestamp set when `startTimer()` is called.
    private var questionStartTime: Date?

    init(level: Int) {
        self.currentDifficulty = DifficultyLevel.getLevel(level)
    }


    // MARK: - Question Generation

    /// Returns a fresh MathChallenge appropriate for the current difficulty.
    /// For subtraction, ensures first >= second (no negative results for kids).
    /// For division, builds the question backwards to guarantee clean integers.
    func generateChallenge() -> MathChallenge {
        let operation = currentDifficulty.operations.randomElement() ?? .addition
        var first  = Int.random(in: currentDifficulty.numberRange)
        var second = Int.random(in: currentDifficulty.numberRange)

        if operation == .subtraction && second > first {
            swap(&first, &second)
        }

        // Division: derive question from answer so there's never a remainder
        if operation == .division {
            let divisor  = max(1, Int.random(in: 1...max(1, currentDifficulty.maxNumber / 3)))
            let quotient = max(1, Int.random(in: 1...max(1, currentDifficulty.maxNumber / divisor)))
            return MathChallenge(
                firstNumber: divisor * quotient,
                secondNumber: divisor,
                operation: .division,
                correctAnswer: quotient,
                difficulty: currentDifficulty
            )
        }

        return MathChallenge(
            firstNumber: first,
            secondNumber: second,
            operation: operation,
            correctAnswer: operation.calculate(first, second),
            difficulty: currentDifficulty
        )
    }


    // MARK: - Timer

    /// Start measuring response time. Call when a question appears on screen.
    func startTimer() {
        questionStartTime = Date()
    }

    /// Stop measuring and return elapsed seconds. Call when the player answers.
    ///
    /// Marked @discardableResult so callers who don't need the time won't
    /// get a compiler warning for ignoring the return value.
    @discardableResult
    func stopTimer() -> TimeInterval {
        let elapsed = questionStartTime.map { Date().timeIntervalSince($0) } ?? 5.0
        questionStartTime = nil   // reset so stale time can't be accidentally reused
        return elapsed
    }


    // MARK: - Performance Recording

    /// Record the result of one answer and return difficulty-change flags.
    ///
    /// - Returns:
    ///   `shouldLevelUp`   true when player is on a hot streak (5 in a row
    ///                     correct, or ≥ 80% in last 5).
    ///   `shouldLevelDown` true when player is struggling (3 wrong in a row,
    ///                     or ≤ 40% in last 5).
    func recordAnswer(isCorrect: Bool) -> (shouldLevelUp: Bool, shouldLevelDown: Bool) {
        // If stopTimer() was already called, questionStartTime is nil and we
        // fall back to a safe default of 5 seconds.
        let responseTime = questionStartTime.map { Date().timeIntervalSince($0) } ?? 5.0
        isCorrect
            ? metrics.recordCorrect(responseTime: responseTime)
            : metrics.recordIncorrect(responseTime: responseTime)
        return evaluateDifficultyAdjustment()
    }

    private func evaluateDifficultyAdjustment() -> (shouldLevelUp: Bool, shouldLevelDown: Bool) {
        let rate = metrics.recentSuccessRate
        let up   = metrics.correctStreak >= 5   || (metrics.lastFiveResults.count >= 5 && rate >= 0.8)
        let down = metrics.incorrectStreak >= 3 || (metrics.lastFiveResults.count >= 5 && rate <= 0.4)
        return (up, down)
    }


    // MARK: - Difficulty Adjustment

    /// Move difficulty up (+1) or down (-1). Clamped to 1–10.
    func adjustDifficulty(levelChange: Int) {
        let newLevel = max(1, min(10, currentDifficulty.level + levelChange))
        currentDifficulty = DifficultyLevel.getLevel(newLevel)
    }

    /// The current 1–10 level number. Read by the UI and by TugOfWarState
    /// to scale how hard the CPU pulls.
    var currentLevel: Int { currentDifficulty.level }
}
