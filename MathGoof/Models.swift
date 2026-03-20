import SwiftUI

// MARK: - Models.swift
// ─────────────────────────────────────────────────────────────────────────────
// This file holds ALL the pure data types for the game:
//   • MathChallenge   — one question (numbers, operation, answers)
//   • DifficultyLevel — settings for each of the 10 levels
//   • PerformanceMetrics — tracks streaks and success rate
//   • GameState       — the classic-mode persistent state
//   • Avatar          — a selectable character for Tug of War
//   • RopePosition    — the single value that drives the rope animation
//
// Why keep everything here?
//   Data models don't import SwiftUI views and don't own any UI state, so
//   they compile fast and are easy to unit-test. Keeping them together means
//   you have ONE place to look when you want to understand the data shape.
// ─────────────────────────────────────────────────────────────────────────────


// MARK: - MathChallenge

/// One question shown to the player.
///
/// This is a VALUE TYPE (struct) — every time the engine generates a new
/// challenge, it creates a fresh copy. There's no shared mutable state,
/// which makes bugs from accidental mutation impossible.
struct MathChallenge {
    let firstNumber: Int
    let secondNumber: Int
    let operation: Operation
    let correctAnswer: Int
    let difficulty: DifficultyLevel

    // ── Operation enum ────────────────────────────────────────────────────────
    // Using an enum instead of a String means the compiler catches typos.
    // The `rawValue` is the symbol shown in the question text.
    enum Operation: String, CaseIterable {
        case addition       = "+"
        case subtraction    = "−"
        case multiplication = "×"
        case division       = "÷"

        /// Performs the actual arithmetic. Centralising this here means the
        /// engine never has to do a switch itself — it just calls `.calculate`.
        func calculate(_ a: Int, _ b: Int) -> Int {
            switch self {
            case .addition:       return a + b
            case .subtraction:    return a - b
            case .multiplication: return a * b
            case .division:       return b == 0 ? 0 : a / b
            }
        }
    }

    /// All 3 answer choices in a fixed random order, generated ONCE at init.
    ///
    /// Why stored instead of computed?
    ///   The old computed properties called Int.random() and .shuffled() on
    ///   every access. SwiftUI re-renders on every @Published change — including
    ///   timerFraction ticking 20x/sec — so the answers reshuffled constantly,
    ///   making it impossible to tap one. Storing the result once at init time
    ///   fixes the order for the lifetime of the challenge.
    let allAnswers: [Int]

    init(firstNumber: Int,
         secondNumber: Int,
         operation: Operation,
         correctAnswer: Int,
         difficulty: DifficultyLevel) {
        self.firstNumber   = firstNumber
        self.secondNumber  = secondNumber
        self.operation     = operation
        self.correctAnswer = correctAnswer
        self.difficulty    = difficulty

        // Generate 2 distinct wrong answers, then shuffle all 3 exactly once
        var wrong: Set<Int> = []
        let range = max(difficulty.answerRange, 5)
        while wrong.count < 2 {
            let offset = Int.random(in: 1...range)
            let candidate = Bool.random() ? correctAnswer + offset : correctAnswer - offset
            if candidate != correctAnswer && candidate >= 0 {
                wrong.insert(candidate)
            }
        }
        var all = Array(wrong)
        all.append(correctAnswer)
        self.allAnswers = all.shuffled()
    }

    /// The formatted equation string shown in the UI, e.g. "7 + 5 ="
    var questionText: String {
        "\(firstNumber) \(operation.rawValue) \(secondNumber) ="
    }
}


// MARK: - DifficultyLevel

/// All the parameters that control how hard a given level is.
///
/// Making this a value type (struct) means levels are immutable once created —
/// you can't accidentally change level 3's number range while playing level 7.
struct DifficultyLevel {
    let level: Int
    let numberRange: ClosedRange<Int>
    let operations: [MathChallenge.Operation]
    let maxNumber: Int
    let answerRange: Int        // how far wrong answers can stray from the correct one
    let timeHint: TimeInterval  // future use: on-screen time hint

    // The full 10-level progression. Levels 1–3 are addition only (warm-up).
    // Subtraction is introduced at level 4. Multiplication at level 7.
    static let levels: [DifficultyLevel] = [
        DifficultyLevel(level: 1,  numberRange: 1...3,  operations: [.addition],                                    maxNumber: 3,  answerRange: 2,  timeHint: 10),
        DifficultyLevel(level: 2,  numberRange: 1...5,  operations: [.addition],                                    maxNumber: 5,  answerRange: 3,  timeHint: 8),
        DifficultyLevel(level: 3,  numberRange: 1...8,  operations: [.addition],                                    maxNumber: 8,  answerRange: 4,  timeHint: 7),
        DifficultyLevel(level: 4,  numberRange: 1...10, operations: [.addition, .subtraction],                      maxNumber: 10, answerRange: 5,  timeHint: 8),
        DifficultyLevel(level: 5,  numberRange: 3...12, operations: [.addition, .subtraction],                      maxNumber: 12, answerRange: 5,  timeHint: 7),
        DifficultyLevel(level: 6,  numberRange: 5...15, operations: [.addition, .subtraction],                      maxNumber: 15, answerRange: 6,  timeHint: 7),
        DifficultyLevel(level: 7,  numberRange: 2...10, operations: [.addition, .subtraction, .multiplication],     maxNumber: 10, answerRange: 8,  timeHint: 10),
        DifficultyLevel(level: 8,  numberRange: 3...12, operations: [.addition, .subtraction, .multiplication],     maxNumber: 12, answerRange: 10, timeHint: 9),
        DifficultyLevel(level: 9,  numberRange: 5...15, operations: [.addition, .subtraction, .multiplication],     maxNumber: 15, answerRange: 12, timeHint: 9),
        DifficultyLevel(level: 10, numberRange: 5...20, operations: [.addition, .subtraction, .multiplication],     maxNumber: 20, answerRange: 15, timeHint: 12),
    ]

    /// Safe lookup — clamps to the valid 1–10 range so out-of-bounds calls
    /// never crash.
    static func getLevel(_ level: Int) -> DifficultyLevel {
        let index = min(level - 1, levels.count - 1)
        return levels[max(0, index)]
    }
}


// MARK: - PerformanceMetrics

/// Tracks answer history so the AdaptiveEngine can decide whether to raise
/// or lower the difficulty.
///
/// `Codable` lets us serialize this to UserDefaults for save/load later.
struct PerformanceMetrics: Codable {
    var correctStreak: Int   = 0
    var incorrectStreak: Int = 0
    var totalCorrect: Int    = 0
    var totalIncorrect: Int  = 0
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
        if lastFiveResults.count > 5 { lastFiveResults.removeFirst() }
    }

    /// A value between 0.0 and 1.0 representing how well the player is doing
    /// over their last 5 answers. 0.5 is the starting "neutral" assumption.
    var recentSuccessRate: Double {
        guard !lastFiveResults.isEmpty else { return 0.5 }
        let correct = lastFiveResults.filter { $0 }.count
        return Double(correct) / Double(lastFiveResults.count)
    }
}


// MARK: - GameState  (Classic mode)

/// Persistent state for the classic game mode. Saved to UserDefaults.
struct GameState: Codable {
    var currentLevel: Int            = 1
    var totalQuestionsAnswered: Int  = 0
    var lifetimeCorrect: Int         = 0
    var lastPlayedDate: Date         = Date()
    var consecutiveDaysPlayed: Int   = 1
    var characterColor: CharacterColor = .orange

    enum CharacterColor: String, Codable, CaseIterable {
        case orange, blue, green, purple, pink

        var gradient: [Color] {
            switch self {
            case .orange: return [.orange, .yellow]
            case .blue:   return [.blue,   .cyan]
            case .green:  return [.green,  .mint]
            case .purple: return [.purple, .indigo]
            case .pink:   return [.pink,   .red]
            }
        }
    }
}


// MARK: - Avatar

/// A selectable fighter character used in Tug of War mode.
///
/// `Identifiable` — required for SwiftUI's ForEach to track items uniquely.
/// `Equatable`    — lets us compare avatars with `==` instead of comparing IDs.
struct Avatar: Identifiable, Equatable {

    /// Stable string ID — we use a readable slug ("wizard") rather than a UUID
    /// so it's easy to debug and could be stored in UserDefaults if needed.
    let id: String

    /// The emoji shown as the character's face on screen.
    let emoji: String

    /// Display name shown in the picker grid.
    let name: String

    /// Two-color gradient for the avatar's background circle.
    let colors: [Color]

    /// A short trash-talk / battle cry shown on screen when this character pulls.
    let battleCry: String

    // ── Roster ────────────────────────────────────────────────────────────────
    // Defined as a static constant so any file can access `Avatar.allAvatars`
    // without creating an instance. Think of it like a global lookup table.
    static let allAvatars: [Avatar] = [
        Avatar(id: "wizard",  emoji: "🧙‍♂️", name: "The Wizard",   colors: [.purple, .indigo], battleCry: "My spells ARE numbers!"),
        Avatar(id: "robot",   emoji: "🤖",  name: "Robo-Rex",     colors: [.gray,   .blue],   battleCry: "Calculating... CRUSH!"),
        Avatar(id: "lion",    emoji: "🦁",  name: "Leo",          colors: [.orange, .yellow], battleCry: "ROAR-ithmetic!"),
        Avatar(id: "rocket",  emoji: "🚀",  name: "Rocket Kid",   colors: [.red,    .orange], battleCry: "Math at light speed!"),
        Avatar(id: "ninja",   emoji: "🥷",  name: "Math Ninja",   colors: [.black,  .gray],   battleCry: "Silent but correct."),
        Avatar(id: "unicorn", emoji: "🦄",  name: "Uni",          colors: [.pink,   .purple], battleCry: "Magic + math = win!"),
    ]
}


// MARK: - RopePosition

/// The single value that controls everything about the rope visually.
///
/// Range: -1.0 (CPU wins) ... 0.0 (center/start) ... +1.0 (player wins)
///
/// Why a struct with helper methods rather than a plain Double?
///   Centralising the win-condition logic here means `TugOfWarState` doesn't
///   need to repeat `abs(value) >= 1.0` in multiple places. The model owns
///   its own rules.
struct RopePosition {
    var value: Double = 0.0

    /// True once the game is definitively over (rope fully to either side).
    var isGameOver: Bool  { abs(value) >= 1.0 }
    var playerWins: Bool  { value >= 1.0 }
    var cpuWins: Bool     { value <= -1.0 }

    /// Is the knot dangerously close to one edge? Used to trigger tension sound.
    var isNearEdge: Bool  { abs(value) > 0.75 }
}
