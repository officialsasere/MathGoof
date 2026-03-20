import SwiftUI

// MARK: - PlayerProfile.swift
// ─────────────────────────────────────────────────────────────────────────────
// Purpose: Persistent player data for Feature 6 (Player Profile & High Scores).
//
// Stores:
//   • playerName       — entered once on first launch
//   • bestLevel        — highest level ever reached
//   • totalStars       — lifetime star count across all runs
//   • starsPerLevel    — [level: stars] so the level map can show progress
//   • fastestAnswerMs  — personal best response time in milliseconds
//
// Why a separate file?
//   Profile data outlives any single game session. Keeping it here means
//   TugOfWarState can import and mutate it without knowing about UI, and
//   AvatarPickerView can display it without knowing about game logic.
//
// Persistence strategy:
//   We use UserDefaults + JSONEncoder/Decoder. This is appropriate for small
//   structured data like a player profile. For larger data (e.g. thousands of
//   game replays) you'd use CoreData or a file in the Documents directory.
// ─────────────────────────────────────────────────────────────────────────────

// MARK: - LevelResult

/// Records the outcome of one level attempt — used to show stars on the
/// game-over screen and in a future level map.
///
/// `Codable` so it can be serialised into UserDefaults as JSON.
struct LevelResult: Codable {

    /// The level number (1–10).
    let level: Int

    /// Stars awarded: 1 (won, barely), 2 (won comfortably), 3 (dominant win).
    /// 0 means the level was attempted but not yet won.
    let stars: Int

    /// The rope position at the moment the player won (0.0–1.0).
    /// Stored for future use (e.g. showing "close call" vs "crushing win").
    let finalRopePosition: Double

    /// How many correct answers the player got in this round.
    let correctAnswers: Int

    // MARK: - Star calculation

    /// Derives a 1–3 star rating from the rope's final position.
    ///
    /// The rope goes from 0.0 (centre start) to 1.0 (full player win).
    /// We measure how far past centre the player got at the winning moment:
    ///
    ///   position ≥ 0.85  → 3 stars  (dominant — rope nearly maxed out)
    ///   position ≥ 0.65  → 2 stars  (comfortable win)
    ///   position ≥ 1.00  → 1 star   (just scraped past the line)
    ///
    /// Note: the player always wins at position = 1.0, so the rating
    /// reflects HOW they won (did they coast it or barely make it?).
    /// We use the position at the moment the winning answer was given
    /// (before the rope physically reaches 1.0) for a fairer measurement.
    static func stars(for ropePosition: Double) -> Int {
        if ropePosition >= 0.75 { return 3 }
        if ropePosition >= 0.40 { return 2 }
        return 1
    }
}


// MARK: - PlayerProfile

/// All persistent data about one player. One instance lives in `MathGoofApp`
/// and is passed down to views that need to read or update it.
///
/// `ObservableObject` so SwiftUI views can react to profile changes (e.g.
/// the avatar picker re-renders when the player earns a new star).
class PlayerProfile: ObservableObject {

    // MARK: - Persistence key
    private static let key = "mathGoof_playerProfile_v1"

    // MARK: - Published properties

    /// The player's chosen display name. Empty string = not yet set.
    @Published var playerName: String

    /// The highest level number the player has ever beaten.
    @Published var bestLevel: Int

    /// Total stars earned across all time (sum of all level results).
    @Published var totalStars: Int

    /// Best result per level. Key = level number (1–10).
    /// Only stores the BEST result if a level has been played multiple times.
    @Published var starsPerLevel: [Int: Int]

    /// Personal best response time in milliseconds. 0 = not yet set.
    @Published var fastestAnswerMs: Int

    // MARK: - Feature 7: Daily Challenge

    /// The date string ("yyyy-MM-dd") of the last day the player completed
    /// the daily challenge. Empty = never played.
    @Published var lastDailyChallengeDate: String

    /// How many consecutive days the player has completed the daily challenge.
    @Published var dailyChallengeStreak: Int

    /// True if the player has already completed today's daily challenge.
    var dailyChallengePlayedToday: Bool {
        lastDailyChallengeDate == Self.todayString
    }

    /// "yyyy-MM-dd" for today's date, used as the daily seed.
    static var todayString: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    /// An integer seed derived from today's date.
    /// All players on the same day get the same seed → same questions.
    static var todaySeed: Int {
        todayString.unicodeScalars.reduce(0) { $0 * 31 + Int($1.value) }
    }


    // MARK: - Codable backing struct
    // Swift doesn't let us make a class with @Published properties
    // directly Codable in a clean way, so we use a private nested struct
    // as the serialisation target and convert to/from it on save/load.

    private struct Snapshot: Codable {
        var playerName:      String
        var bestLevel:       Int
        var totalStars:      Int
        var starsPerLevel:   [Int: Int]
        var fastestAnswerMs: Int
        // Feature 7 — Daily challenge
        var lastDailyChallengeDate: String   // "yyyy-MM-dd" of last play
        var dailyChallengeStreak:   Int      // consecutive days played
    }


    // MARK: - Init

    init() {
        // Try to load a saved snapshot from UserDefaults.
        // If nothing is saved yet, use sensible defaults.
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let snap = try? JSONDecoder().decode(Snapshot.self, from: data) {
            playerName             = snap.playerName
            bestLevel              = snap.bestLevel
            totalStars             = snap.totalStars
            starsPerLevel          = snap.starsPerLevel
            fastestAnswerMs        = snap.fastestAnswerMs
            lastDailyChallengeDate = snap.lastDailyChallengeDate
            dailyChallengeStreak   = snap.dailyChallengeStreak
        } else {
            playerName             = ""
            bestLevel              = 0
            totalStars             = 0
            starsPerLevel          = [:]
            fastestAnswerMs        = 0
            lastDailyChallengeDate = ""
            dailyChallengeStreak   = 0
        }
    }


    // MARK: - Update after a round

    /// Called by TugOfWarState when the player wins a level.
    ///
    /// - Parameters:
    ///   - level:            The level number that was just beaten.
    ///   - ropePosition:     The rope's position at win time (used for stars).
    ///   - correctAnswers:   How many correct answers the player gave.
    ///   - fastestAnswerMs:  The fastest single response in this round (ms).
    func recordWin(level: Int,
                   ropePosition: Double,
                   correctAnswers: Int,
                   fastestAnswerMs: Int) {

        let earned = LevelResult.stars(for: ropePosition)

        // Only update stars if this run is better than the previous best
        let previous = starsPerLevel[level] ?? 0
        if earned > previous {
            starsPerLevel[level] = earned
            // Adjust total: remove old contribution, add new
            totalStars = totalStars - previous + earned
        }

        // Update best level
        if level > bestLevel { bestLevel = level }

        // Update fastest answer (lower is better; 0 means unset)
        if fastestAnswerMs > 0 {
            if self.fastestAnswerMs == 0 || fastestAnswerMs < self.fastestAnswerMs {
                self.fastestAnswerMs = fastestAnswerMs
            }
        }

        save()
    }

    /// Records that the player completed today's daily challenge.
    func recordDailyChallenge() {
        let today = Self.todayString
        guard lastDailyChallengeDate != today else { return }  // already recorded

        // Check if this extends an existing streak (played yesterday)
        let calendar = Calendar.current
        if let lastDate = DateFormatter().date(from: lastDailyChallengeDate),
           calendar.isDateInYesterday(lastDate) {
            dailyChallengeStreak += 1
        } else if lastDailyChallengeDate.isEmpty {
            dailyChallengeStreak = 1
        } else {
            dailyChallengeStreak = 1   // streak broken, restart at 1
        }

        lastDailyChallengeDate = today
        save()
    }

    /// Sets the player's name and saves immediately.
    func setName(_ name: String) {
        playerName = name.trimmingCharacters(in: .whitespaces)
        save()
    }

    /// Stars earned for a specific level. 0 if not yet beaten.
    func stars(for level: Int) -> Int {
        starsPerLevel[level] ?? 0
    }

    /// Total stars earned so far, computed from starsPerLevel.
    /// (totalStars is the same value, this is just a convenience alias.)
    var displayStars: String {
        "⭐️ \(totalStars)"
    }


    // MARK: - Persistence

    private func save() {
        let snap = Snapshot(
            playerName:             playerName,
            bestLevel:              bestLevel,
            totalStars:             totalStars,
            starsPerLevel:          starsPerLevel,
            fastestAnswerMs:        fastestAnswerMs,
            lastDailyChallengeDate: lastDailyChallengeDate,
            dailyChallengeStreak:   dailyChallengeStreak
        )
        if let data = try? JSONEncoder().encode(snap) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    /// Wipes all saved data. Useful for testing or a "reset progress" button.
    func reset() {
        playerName             = ""
        bestLevel              = 0
        totalStars             = 0
        starsPerLevel          = [:]
        fastestAnswerMs        = 0
        lastDailyChallengeDate = ""
        dailyChallengeStreak   = 0
        UserDefaults.standard.removeObject(forKey: Self.key)
    }
}
