import Foundation

// MARK: - SeededRandom.swift
// ─────────────────────────────────────────────────────────────────────────────
// Purpose: A deterministic pseudo-random number generator (PRNG) for the
//   daily challenge. Given the same seed (derived from today's date), it
//   always produces the same sequence of numbers — so every player sees
//   the same questions on the same day.
//
// Algorithm: xorshift64 — a simple, fast, well-distributed PRNG that is
//   good enough for a children's game and requires no external libraries.
//
// Why not use Swift's built-in random?
//   SystemRandomNumberGenerator is intentionally non-seeded for security.
//   We need a seeded generator so two players on different devices get
//   identical question sequences when given the same date seed.
// ─────────────────────────────────────────────────────────────────────────────

struct SeededRandom {

    /// The internal state. Changes with every call to `next()`.
    private var state: UInt64

    /// Initialise with any non-zero 64-bit seed.
    init(seed: Int) {
        // XOR with a large prime to avoid a degenerate all-zeros state
        // if the caller passes seed = 0.
        state = UInt64(bitPattern: Int64(seed)) ^ 0x9E3779B97F4A7C15
        if state == 0 { state = 1 }
    }

    // ── Core xorshift64 step ──────────────────────────────────────────────────
    // Each call mutates `state` and returns a new pseudo-random UInt64.
    // The three XOR-shift constants are chosen for maximum period length.
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    /// Returns a random Int in the closed range [min, max].
    mutating func nextInt(in range: ClosedRange<Int>) -> Int {
        let span = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int(next() % span)
    }

    /// Returns a random Bool.
    mutating func nextBool() -> Bool {
        return next() % 2 == 0
    }

    /// Returns a random element from an array. Crashes if array is empty
    /// (same contract as Array.randomElement()!).
    mutating func nextElement<T>(from array: [T]) -> T {
        let index = Int(next() % UInt64(array.count))
        return array[index]
    }
}


// MARK: - DailyChallengeEngine

/// Generates a fixed sequence of 10 questions for today's daily challenge.
/// Questions are harder than normal (level 5 difficulty) to make the
/// daily challenge feel special.
///
/// Usage:
///   let engine = DailyChallengeEngine()
///   let questions = engine.generateQuestions()  // always same 10 for today
struct DailyChallengeEngine {

    /// Today's seed, derived from the date string "yyyy-MM-dd".
    private let seed: Int

    init(seed: Int = PlayerProfile.todaySeed) {
        self.seed = seed
    }

    /// Generates exactly 10 questions using the seeded RNG.
    /// Calling this twice on the same day always returns identical questions.
    func generateQuestions() -> [MathChallenge] {
        var rng = SeededRandom(seed: seed)
        let difficulty = DifficultyLevel.getLevel(5)  // fixed at level 5

        var questions: [MathChallenge] = []
        for _ in 0..<10 {
            questions.append(makeQuestion(difficulty: difficulty, rng: &rng))
        }
        return questions
    }

    private func makeQuestion(difficulty: DifficultyLevel,
                               rng: inout SeededRandom) -> MathChallenge {

        let operation = rng.nextElement(from: difficulty.operations)
        var first  = rng.nextInt(in: difficulty.numberRange)
        var second = rng.nextInt(in: difficulty.numberRange)

        if operation == .subtraction && second > first {
            let tmp = first; first = second; second = tmp
        }

        let answer = operation.calculate(first, second)

        // Generate 2 wrong answers deterministically
        var wrong: [Int] = []
        while wrong.count < 2 {
            let offset = rng.nextInt(in: 1...max(difficulty.answerRange, 5))
            let candidate = rng.nextBool() ? answer + offset : answer - offset
            if candidate != answer && candidate >= 0 && !wrong.contains(candidate) {
                wrong.append(candidate)
            }
        }

        // Shuffle all 3 answers deterministically
        var all = wrong + [answer]
        // Fisher-Yates shuffle using seeded RNG
        for i in stride(from: all.count - 1, through: 1, by: -1) {
            let j = rng.nextInt(in: 0...i)
            all.swapAt(i, j)
        }

        return MathChallenge(
            firstNumber:   first,
            secondNumber:  second,
            operation:     operation,
            correctAnswer: answer,
            difficulty:    difficulty
        )
    }
}
