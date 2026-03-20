import AVFoundation
import SwiftUI
import AudioToolbox



class TugAudioManager: ObservableObject {

    // ── Haptic generators ─────────────────────────────────────────────────────
    // We pre-create these because instantiating UIFeedbackGenerator has a
    // slight delay — pre-warming it removes latency on first use.

    private let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let notification = UINotificationFeedbackGenerator()

    // ─────────────────────────────────────────────────────────────────────────
    // init
    // "Prepare" calls tell the OS to spin up the haptic engine now so
    // there's no gap between user action and physical feedback.
    // ─────────────────────────────────────────────────────────────────────────
    init() {
        heavyImpact.prepare()
        mediumImpact.prepare()
        lightImpact.prepare()
        notification.prepare()
    }


    // MARK: - Correct Pull

    /// Played when the child answers correctly and their avatar pulls the rope.
    ///
    /// Sound story: a grunt of effort (thud) → rope strain creak → triumphant
    ///   short chime. Three beats mirror the three stages of actually tugging.
    func playCorrectPull() {
        // Beat 1: Heavy thud — the physical effort of pulling
        heavyImpact.impactOccurred(intensity: 1.0)
        AudioServicesPlaySystemSound(1057)   // Short punchy hit

        // Beat 2 (0.15s later): Rope "creaking" strain sound
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.mediumImpact.impactOccurred(intensity: 0.7)
            AudioServicesPlaySystemSound(1104)   // Bright chime
        }

        // Beat 3 (0.35s later): Victory mini-chime — you moved the rope!
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.lightImpact.impactOccurred(intensity: 0.5)
            AudioServicesPlaySystemSound(1025)   // Positive completion
        }
    }


    // MARK: - Wrong Pull

    /// Played when the child answers incorrectly and the CPU pulls back.
    ///
    /// Sound story: a surprised yelp (sharp buzz) → the rope sliding the
    ///   wrong way (descending tone) → a moment of suspense.
    func playWrongPull() {
        // Beat 1: Sharp negative buzz — "uh oh!"
        notification.notificationOccurred(.error)
        AudioServicesPlaySystemSound(1053)   // Negative thud

        // Beat 2 (0.2s later): The CPU's counter-pull reverberation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.heavyImpact.impactOccurred(intensity: 0.6)
            AudioServicesPlaySystemSound(1006)   // Low beep (sounds like sliding)
        }
    }


    // MARK: - Match Start

    /// Played when the battle screen first appears.
    ///
    /// Sound story: a drumroll build (3 escalating light taps) → a BIG
    ///   countdown gong. Signals to the kid: "get ready, it's on!"
    func playMatchStart() {
        // Drum roll: 3 escalating taps
        for i in 0..<3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.18) { [weak self] in
                let intensity = 0.4 + (Double(i) * 0.3)
                self?.mediumImpact.impactOccurred(intensity: intensity)
                AudioServicesPlaySystemSound(1057)
            }
        }

        // Final gong at beat 4
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.heavyImpact.impactOccurred(intensity: 1.0)
            AudioServicesPlaySystemSound(1036)   // Deep alert gong
        }
    }


    // MARK: - Player Wins

    /// Full victory fanfare when the player pulls the rope all the way across.
    ///
    /// Sound story: rising chime sequence → triumphant fanfare → celebratory
    ///   firework pops. This should feel like crossing a finish line.
    func playPlayerWins() {
        // Rising chime sequence
        let chimeDelays = [0.0, 0.15, 0.3, 0.45]
        for (i, delay) in chimeDelays.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.notification.notificationOccurred(.success)
                AudioServicesPlaySystemSound(i % 2 == 0 ? 1104 : 1025)
            }
        }

        // Big fanfare at the peak
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.heavyImpact.impactOccurred(intensity: 1.0)
            AudioServicesPlaySystemSound(1013)   // Success fanfare
        }

        // Firework pops (3 burst haptics)
        for i in 0..<3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9 + Double(i) * 0.2) { [weak self] in
                self?.heavyImpact.impactOccurred(intensity: 0.8)
                AudioServicesPlaySystemSound(1052)
            }
        }
    }


    // MARK: - CPU Wins

    /// Sombre defeat sound when the CPU pulls the rope across.
    ///
    /// Sound story: a falling "womp womp" tone → a single muted thud at the
    ///   bottom → silence. Should feel deflating but not mean.
    ///
    /// Note: We deliberately keep this SHORT. Research on kids' games shows
    ///   prolonged failure sounds cause frustration and quitting. A quick
    ///   acknowledgement + fast pivot to "try again" is best practice.
    func playCPUWins() {
        // Descending tones
        AudioServicesPlaySystemSound(1053)   // First drop

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.notification.notificationOccurred(.warning)
            AudioServicesPlaySystemSound(1006)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.heavyImpact.impactOccurred(intensity: 0.5)
            AudioServicesPlaySystemSound(1005)   // Low thud at the bottom
        }
    }


    // MARK: - Rope Tension (optional enhancement)

    /// Can be called as the knot gets close to one edge — builds tension.
    /// Haptic pattern mimics a rope under extreme strain (rapid light pulses).
    func playRopeTension() {
        for i in 0..<4 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.08) { [weak self] in
                self?.lightImpact.impactOccurred(intensity: 0.4)
            }
        }
    }
}
