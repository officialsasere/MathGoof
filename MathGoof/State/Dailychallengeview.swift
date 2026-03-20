import SwiftUI

// MARK: - DailyChallengeView.swift
// ─────────────────────────────────────────────────────────────────────────────
// Purpose: The daily challenge. Presents 10 seeded questions against the CPU
//   using the FULL tug-of-war rope mechanic — same physics, same sounds, same
//   animations as the regular game.
//
// How seeding works:
//   DailyChallengeEngine generates 10 questions from today's date as a seed.
//   Same date = same questions for every player worldwide.
//   These questions are injected into TugOfWarState via its daily init, which
//   feeds them through nextQuestion() instead of the adaptive engine.
//   Every other mechanic (rope, CPU drift, timer, streak, power-up) is
//   identical to the normal game.
//
// What's different from a normal level:
//   • Questions are fixed and seeded — not random.
//   • After the 10th question is consumed, the adaptive engine takes over
//     (the game can still end by rope reaching ±1.0 at any point).
//   • On win/loss, DailyResultOverlay shows stars + streak instead of the
//     normal level-complete overlay.
//   • Completion is saved to PlayerProfile (once per day).
// ─────────────────────────────────────────────────────────────────────────────

struct DailyChallengeView: View {

    @ObservedObject var profile: PlayerProfile
    let playerAvatar: Avatar
    let onDone: () -> Void

    /// TugOfWarState initialised with today's seeded questions.
    /// Everything else — rope, CPU, timer, streaks, power-ups — works exactly
    /// as in the regular game because we are reusing TugOfWarState unchanged.
    @StateObject private var game: TugOfWarState
    @StateObject private var audio = TugAudioManager()

    init(profile: PlayerProfile, playerAvatar: Avatar, onDone: @escaping () -> Void) {
        self.profile      = profile
        self.playerAvatar = playerAvatar
        self.onDone       = onDone

        // Generate today's seeded questions and inject them into the game state
        let questions = DailyChallengeEngine().generateQuestions()
        _game = StateObject(
            wrappedValue: TugOfWarState(
                playerAvatar: playerAvatar,
                dailyQuestions: questions,
                profile: nil   // daily wins are handled by DailyResultOverlay
            )
        )
    }

    var body: some View {
        ZStack {
            // ── Background — gold/orange to distinguish from normal levels ────
            LinearGradient(
                colors: [.orange.opacity(0.88), .red.opacity(0.82)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 16) {

                // ── Header ────────────────────────────────────────────────────
                HStack {
                    Button(action: onDone) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.white.opacity(0.7))
                    }

                    Spacer()

                    VStack(spacing: 2) {
                        Text("☀️ Daily Challenge")
                            .font(.system(.headline, design: .rounded).bold())
                            .foregroundColor(.white)
                        Text(PlayerProfile.todayString)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }

                    Spacer()

                    Button(action: { game.toggleSound() }) {
                        Image(systemName: game.isSoundEnabled
                              ? "speaker.wave.2.fill" : "speaker.slash.fill")
                            .font(.title3)
                            .foregroundColor(game.isSoundEnabled
                                             ? .white.opacity(0.7) : .white.opacity(0.3))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                // ── Rope arena ────────────────────────────────────────────────
                GeometryReader { geo in
                    RopeArena(
                        playerAvatar: game.playerAvatar,
                        cpuAvatar: game.cpuAvatar,
                        ropeValue: game.rope.position,
                        flashGreen: game.flashGreen,
                        flashRed: game.flashRed,
                        containerWidth: geo.size.width,
                        cpuMood: game.cpuMood
                    )
                }
                .frame(height: 160)

                // ── Countdown timer ───────────────────────────────────────────
                TimerBar(fraction: game.timerFraction)
                    .padding(.horizontal, 24)

                // ── Power-up button ───────────────────────────────────────────
                ZStack {
                    if game.powerUpReady {
                        Button(action: { game.activatePowerUp() }) {
                            HStack(spacing: 8) {
                                Text("⚡️")
                                Text("SUPER PULL!")
                                    .font(.system(size: 16, weight: .black, design: .rounded))
                                Text("⚡️")
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(
                                LinearGradient(colors: [.yellow, .orange],
                                               startPoint: .leading, endPoint: .trailing)
                            )
                            .cornerRadius(20)
                            .shadow(color: .orange.opacity(0.6), radius: 8)
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(height: 44)
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: game.powerUpReady)

                // ── Streak / battle cry ───────────────────────────────────────
                ZStack {
                    if game.correctStreak >= 2 {
                        HStack(spacing: 6) {
                            Text("🔥")
                            Text("×\(game.correctStreak)")
                                .font(.system(size: 20, weight: .black, design: .rounded))
                                .foregroundColor(.orange)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.2))
                        .cornerRadius(20)
                        .transition(.scale.combined(with: .opacity))
                    } else if let cry = game.activeBattleCry {
                        Text("💬 \(cry)")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.2))
                            .cornerRadius(20)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(height: 36)
                .animation(.spring(response: 0.3, dampingFraction: 0.7),
                           value: game.correctStreak)

                // ── Question ──────────────────────────────────────────────────
                Text(game.currentChallenge.questionText)
                    .font(.system(size: 58, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(radius: 4)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .padding(.horizontal, 20)

                // ── Answer grid ───────────────────────────────────────────────
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 16
                ) {
                    ForEach(game.currentChallenge.allAnswers, id: \.self) { num in
                        AnswerTile(
                            number: num,
                            selectedAnswer: game.selectedAnswer,
                            correctAnswer: game.currentChallenge.correctAnswer
                        ) {
                            if game.isSoundEnabled {
                                num == game.currentChallenge.correctAnswer
                                    ? audio.playCorrectPull()
                                    : audio.playWrongPull()
                            }
                            game.answer(num)
                        }
                    }
                }
                .padding(.horizontal, 24)

                Spacer(minLength: 0)
            }

            // ── Game Over overlay ─────────────────────────────────────────────
            if game.gameOver {
                DailyResultOverlay(
                    playerWon:    game.rope.position >= 0,
                    starsEarned:  game.starsEarned,
                    playerAvatar: playerAvatar,
                    cpuAvatar:    game.cpuAvatar,
                    streak:       profile.dailyChallengeStreak,
                    onDone: {
                        profile.recordDailyChallenge()
                        onDone()
                    }
                )
                .transition(.opacity)
            }
        }
        .onAppear {
            game.startGameLoop()
            if game.isSoundEnabled { audio.playMatchStart() }
        }
        .onChange(of: game.gameOver) { _, isOver in
            if isOver, game.isSoundEnabled {
                game.rope.position >= 0
                    ? audio.playPlayerWins()
                    : audio.playCPUWins()
            }
        }
        .onChange(of: game.rope.isNearEdge) { _, nearEdge in
            if nearEdge, game.isSoundEnabled { audio.playRopeTension() }
        }
        .animation(.easeInOut(duration: 0.3), value: game.gameOver)
    }
}


// MARK: - DailyResultOverlay

/// Shown when the daily challenge rope reaches ±1.0.
/// Shows win/loss result, stars earned, daily streak, and a collect button.
struct DailyResultOverlay: View {
    let playerWon: Bool
    let starsEarned: Int
    let playerAvatar: Avatar
    let cpuAvatar: Avatar
    let streak: Int         // streak BEFORE recording today
    let onDone: () -> Void

    @State private var scale: CGFloat = 0.4
    @State private var showConfetti = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.78).ignoresSafeArea()

            if showConfetti && playerWon { ConfettiOverlay() }

            VStack(spacing: 24) {

                Text(playerWon ? playerAvatar.emoji : cpuAvatar.emoji)
                    .font(.system(size: 64))

                VStack(spacing: 10) {
                    Text(playerWon ? "☀️ Challenge Won!" : "Not today... 💪")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundColor(playerWon ? .yellow : .white)

                    if playerWon {
                        StarRatingView(stars: starsEarned)

                        if streak >= 0 {
                            HStack(spacing: 8) {
                                Text("🔥")
                                Text("\(streak + 1) day streak!")
                                    .font(.system(.body, design: .rounded).bold())
                                    .foregroundColor(.orange)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.orange.opacity(0.2))
                            .cornerRadius(16)
                        }
                    } else {
                        Text("The CPU pulled harder today.")
                            .font(.title3)
                            .foregroundColor(.white.opacity(0.8))

                        Text("Come back tomorrow for a new challenge!")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                }

                Button(action: onDone) {
                    Text(playerWon ? "Collect Reward 🌟" : "Back to Map")
                        .font(.system(.title2, design: .rounded).bold())
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: playerWon ? [.orange, .red] : [.blue, .indigo],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(18)
                }
                .padding(.horizontal, 30)
            }
            .padding(32)
            .scaleEffect(scale)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.65)) { scale = 1.0 }
            if playerWon {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { showConfetti = true }
            }
        }
    }
}
