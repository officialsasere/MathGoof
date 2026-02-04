import Foundation

// MARK: - Adaptive Engine

class AdaptiveEngine {
    private var metrics = PerformanceMetrics()
    private var currentDifficulty: DifficultyLevel
    private var questionStartTime: Date?
    
    init(level: Int) {
        self.currentDifficulty = DifficultyLevel.getLevel(level)
    }
    
    func generateChallenge() -> MathChallenge {
        let operation = currentDifficulty.operations.randomElement() ?? .addition
        var first = Int.random(in: currentDifficulty.numberRange)
        var second = Int.random(in: currentDifficulty.numberRange)
        
        if operation == .subtraction && second > first {
            swap(&first, &second)
        }
        
        return MathChallenge(
            firstNumber: first,
            secondNumber: second,
            operation: operation,
            correctAnswer: operation.calculate(first, second),
            difficulty: currentDifficulty
        )
    }
    
    func startTimer() {
        questionStartTime = Date()
    }
    
    func recordAnswer(isCorrect: Bool) -> (shouldLevelUp: Bool, shouldLevelDown: Bool) {
        let responseTime = questionStartTime.map { Date().timeIntervalSince($0) } ?? 5.0
        isCorrect ? metrics.recordCorrect(responseTime: responseTime) : metrics.recordIncorrect(responseTime: responseTime)
        return evaluateDifficultyAdjustment()
    }
    
    private func evaluateDifficultyAdjustment() -> (shouldLevelUp: Bool, shouldLevelDown: Bool) {
        let rate = metrics.recentSuccessRate
        let up = metrics.correctStreak >= 5 || (metrics.lastFiveResults.count >= 5 && rate >= 0.8)
        let down = metrics.incorrectStreak >= 3 || (metrics.lastFiveResults.count >= 5 && rate <= 0.4)
        return (up, down)
    }
    
    func adjustDifficulty(levelChange: Int) {
        let newLevel = max(1, min(10, currentDifficulty.level + levelChange))
        currentDifficulty = DifficultyLevel.getLevel(newLevel)
    }
    
    var currentLevel: Int { currentDifficulty.level }
}
