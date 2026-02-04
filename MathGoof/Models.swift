import SwiftUI

// MARK: - Math Challenge

struct MathChallenge {
    let firstNumber: Int
    let secondNumber: Int
    let operation: Operation
    let correctAnswer: Int
    let difficulty: DifficultyLevel
    
    enum Operation: String, CaseIterable {
        case addition = "+"
        case subtraction = "−"
        case multiplication = "×"
        case division = "/"
        
        func calculate(_ a: Int, _ b: Int) -> Int {
            switch self {
            case .addition: return a + b
            case .subtraction: return a - b
            case .multiplication: return a * b
            case .division: return a / b
            }
        }
    }
    
    var wrongAnswers: [Int] {
        var answers: Set<Int> = []
        let range = max(difficulty.answerRange, 5)
        
        while answers.count < 2 {
            let offset = Int.random(in: 1...range)
            let wrongAnswer = Bool.random() ? correctAnswer + offset : correctAnswer - offset
            if wrongAnswer != correctAnswer && wrongAnswer >= 0 {
                answers.insert(wrongAnswer)
            }
        }
        return Array(answers)
    }
    
    var allAnswers: [Int] {
        var answers = wrongAnswers
        answers.append(correctAnswer)
        return answers.shuffled()
    }
    
    var questionText: String {
        "\(firstNumber) \(operation.rawValue) \(secondNumber) ="
    }
}

// MARK: - Difficulty Level

struct DifficultyLevel {
    let level: Int
    let numberRange: ClosedRange<Int>
    let operations: [MathChallenge.Operation]
    let maxNumber: Int
    let answerRange: Int
    let timeHint: TimeInterval
    
    static let levels: [DifficultyLevel] = [
        DifficultyLevel(level: 1, numberRange: 1...3, operations: [.addition], maxNumber: 3, answerRange: 2, timeHint: 10),
        DifficultyLevel(level: 2, numberRange: 1...5, operations: [.addition], maxNumber: 5, answerRange: 3, timeHint: 8),
        DifficultyLevel(level: 3, numberRange: 1...8, operations: [.addition], maxNumber: 8, answerRange: 4, timeHint: 7),
        DifficultyLevel(level: 4, numberRange: 1...10, operations: [.addition, .subtraction], maxNumber: 10, answerRange: 5, timeHint: 8),
        DifficultyLevel(level: 5, numberRange: 3...12, operations: [.addition, .subtraction], maxNumber: 12, answerRange: 5, timeHint: 7),
        DifficultyLevel(level: 6, numberRange: 5...15, operations: [.addition, .subtraction], maxNumber: 15, answerRange: 6, timeHint: 7),
        DifficultyLevel(level: 7, numberRange: 2...10, operations: [.addition, .subtraction, .multiplication], maxNumber: 10, answerRange: 8, timeHint: 10),
        DifficultyLevel(level: 8, numberRange: 3...12, operations: [.addition, .subtraction, .multiplication], maxNumber: 12, answerRange: 10, timeHint: 9),
        DifficultyLevel(level: 9, numberRange: 5...15, operations: [.addition, .subtraction, .multiplication], maxNumber: 15, answerRange: 12, timeHint: 9),
        DifficultyLevel(level: 10, numberRange: 5...20, operations: [.addition, .subtraction, .multiplication], maxNumber: 20, answerRange: 15, timeHint: 12),
    ]
    
    static func getLevel(_ level: Int) -> DifficultyLevel {
        let index = min(level - 1, levels.count - 1)
        return levels[max(0, index)]
    }
}

// MARK: - Performance Metrics

struct PerformanceMetrics: Codable {
    var correctStreak: Int = 0
    var incorrectStreak: Int = 0
    var totalCorrect: Int = 0
    var totalIncorrect: Int = 0
    var averageResponseTime: Double = 0
    var lastFiveResults: [Bool] = []
    
    mutating func recordCorrect(responseTime: TimeInterval) {
        correctStreak += 1
        incorrectStreak = 0
        totalCorrect += 1
        updateAverageResponseTime(responseTime)
        updateLastFive(true)
    }
    
    mutating func recordIncorrect(responseTime: TimeInterval) {
        incorrectStreak += 1
        correctStreak = 0
        totalIncorrect += 1
        updateAverageResponseTime(responseTime)
        updateLastFive(false)
    }
    
    private mutating func updateAverageResponseTime(_ time: TimeInterval) {
        let total = totalCorrect + totalIncorrect
        averageResponseTime = ((averageResponseTime * Double(total - 1)) + time) / Double(total)
    }
    
    private mutating func updateLastFive(_ result: Bool) {
        lastFiveResults.append(result)
        if lastFiveResults.count > 5 {
            lastFiveResults.removeFirst()
        }
    }
    
    var recentSuccessRate: Double {
        guard !lastFiveResults.isEmpty else { return 0.5 }
        let correct = lastFiveResults.filter { $0 }.count
        return Double(correct) / Double(lastFiveResults.count)
    }
}

// MARK: - Game State

struct GameState: Codable {
    var currentLevel: Int = 1
    var totalQuestionsAnswered: Int = 0
    var lifetimeCorrect: Int = 0
    var lastPlayedDate: Date = Date()
    var consecutiveDaysPlayed: Int = 1
    var characterColor: CharacterColor = .orange
    
    enum CharacterColor: String, Codable, CaseIterable {
        case orange, blue, green, purple, pink
        
        var gradient: [Color] {
            switch self {
            case .orange: return [.orange, .yellow]
            case .blue: return [.blue, .cyan]
            case .green: return [.green, .mint]
            case .purple: return [.purple, .indigo]
            case .pink: return [.pink, .red]
            }
        }
    }
}
