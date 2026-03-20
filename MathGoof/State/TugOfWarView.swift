import SwiftUI

// MARK: - TugOfWarView.swift
// ─────────────────────────────────────────────────────────────────────────────
// Purpose: The main battle arena. This view is intentionally "dumb" — it only
//   DISPLAYS state and FORWARDS taps to TugOfWarState. No game logic lives here.
//
// Layout (top → bottom):
//   TopBar          — level indicator + quit button
//   RopeArena       — avatars + animated rope with sliding knot
//   Battle cry      — flashes whoever just pulled
//   Question text   — the math equation
//   Answer grid     — 2×2 grid of large tappable buttons
//   GameOverOverlay — shown when rope reaches ±1.0
// ─────────────────────────────────────────────────────────────────────────────

struct TugOfWarView: View {

    @StateObject private var game: TugOfWarState
    @StateObject private var audio = TugAudioManager()

    /// Callback to return to the AvatarPickerView.
    let onQuit: () -> Void

    // Creating TugOfWarState inside init lets us pass playerAvatar into it.
    // The @StateObject wrapper then owns the object for the view's lifetime.
    init(playerAvatar: Avatar, onQuit: @escaping () -> Void) {
        _game = StateObject(wrappedValue: TugOfWarState(playerAvatar: playerAvatar))
        self.onQuit = onQuit
    }

    var body: some View {
        ZStack {
            // ── Background ────────────────────────────────────────────────────
            LinearGradient(
                colors: [.blue.opacity(0.9), .purple.opacity(0.9)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 16) {

                // ── Top bar ───────────────────────────────────────────────────
                TopBar(
                    playerAvatar: game.playerAvatar,
                    cpuAvatar: game.cpuAvatar,
                    level: game.level,
                    onQuit: onQuit
                )
                .padding(.horizontal, 20)
                .padding(.top, 8)

                // ── Rope arena ────────────────────────────────────────────────
                // GeometryReader gives us the actual pixel width at render time
                // so the rope and knot positions are always accurate regardless
                // of device size (iPhone SE vs iPhone 16 Pro Max vs iPad).
                GeometryReader { geo in
                    RopeArena(
                        playerAvatar: game.playerAvatar,
                        cpuAvatar: game.cpuAvatar,
                        ropeValue: game.rope.position,
                        flashGreen: game.flashGreen,
                        flashRed: game.flashRed,
                        containerWidth: geo.size.width
                    )
                }
                .frame(height: 170)

                // ── Battle cry ────────────────────────────────────────────────
                // Fixed-height container prevents the layout from jumping when
                // the battle cry appears and disappears.
                ZStack {
                    if let cry = game.activeBattleCry {
                        Text("💬 \(cry)")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.2))
                            .cornerRadius(20)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(height: 36)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: game.activeBattleCry)

                // ── Math question ─────────────────────────────────────────────
                Text(game.currentChallenge.questionText)
                    .font(.system(size: 60, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(radius: 4)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .padding(.horizontal, 20)

                // ── Answer grid ───────────────────────────────────────────────
                // 2×2 grid of big buttons. Large font and generous padding make
                // them easy to tap for children with smaller fingers.
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
                            // Play sound BEFORE submitting so the haptic lands
                            // at the exact moment of the tap
                            if num == game.currentChallenge.correctAnswer {
                                audio.playCorrectPull()
                            } else {
                                audio.playWrongPull()
                            }
                            game.answer(num)
                        }
                    }
                }
                .padding(.horizontal, 24)

                Spacer(minLength: 0)
            }

            // ── Game Over Overlay ─────────────────────────────────────────────
            // Sits on top of everything in the ZStack.
            if game.gameOver {
                GameOverOverlay(
                    playerWon: game.rope.position >= 0,
                    currentLevel: game.currentLevel,
                    playerAvatar: game.playerAvatar,
                    cpuAvatar: game.cpuAvatar,
                    onNextLevel: {
                        game.nextLevel()
                        audio.playMatchStart()
                    },
                    onRetry: {
                        game.retryLevel()
                        audio.playMatchStart()
                    },
                    onQuit: onQuit
                )
                // .id forces SwiftUI to fully destroy and recreate this view
                // each time the level changes. Without it, SwiftUI reuses the
                // existing GameOverOverlay and its @State (scale, showConfetti)
                // stays stale — the overlay appears frozen and never dismisses.
                .id("overlay-\(game.currentLevel)")
                .transition(.opacity)
            }
        }
        .onAppear {
            game.startGameLoop()
            audio.playMatchStart()
        }
        .onChange(of: game.gameOver) { _, isOver in
            if isOver {
                game.rope.position >= 0
                    ? audio.playPlayerWins()
                    : audio.playCPUWins()
            }
        }
        .onChange(of: game.rope.isNearEdge) { _, nearEdge in
            if nearEdge { audio.playRopeTension() }
        }
    }
}


// MARK: - TopBar

/// Level indicator flanked by the two avatar emojis, plus a quit button.
struct TopBar: View {
    let playerAvatar: Avatar
    let cpuAvatar: Avatar
    let level: Int
    let onQuit: () -> Void

    var body: some View {
        HStack {
            Text(playerAvatar.emoji).font(.title)

            Spacer()

            VStack(spacing: 2) {
                Text("Level \(level)")
                    .font(.system(.title2, design: .rounded).bold())
                    .foregroundColor(.yellow)
                Text("vs CPU")
                    .font(.caption.bold())
                    .foregroundColor(.white.opacity(0.6))
            }

            Spacer()

            Text(cpuAvatar.emoji).font(.title)

            Button(action: onQuit) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.leading, 8)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .background(Color.white.opacity(0.12))
        .cornerRadius(16)
    }
}


// MARK: - RopeArena

/// The visual heart of the game: two large avatar emojis with an animated
/// rope stretched between them. A knot slides based on the rope value.
///
/// How the rope position math works:
///   `ropeValue` goes from -1.0 to +1.0.
///   The knot's X offset from the centre of the view = ropeValue × (width/2 − margin)
///   At ropeValue = 0    → knot is exactly at centre
///   At ropeValue = +1.0 → knot is at the left edge (player's side)
///   At ropeValue = -1.0 → knot is at the right edge (CPU's side)
struct RopeArena: View {
    let playerAvatar: Avatar
    let cpuAvatar: Avatar
    let ropeValue: Double
    let flashGreen: Bool
    let flashRed: Bool
    let containerWidth: CGFloat

    /// How far from each edge the avatar sits (in points).
    private let avatarPadding: CGFloat = 50

    /// Maximum distance the knot can travel from centre (knot stays inside).
    private var maxKnotOffset: CGFloat {
        containerWidth / 2 - avatarPadding - 30
    }

    var body: some View {
        ZStack {
            // ── Rope ──────────────────────────────────────────────────────────
            // The rope is a capsule-shaped rectangle coloured brown.
            // Two coloured overlays grow from the winning side.
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.55, green: 0.35, blue: 0.15),
                            Color(red: 0.72, green: 0.52, blue: 0.24),
                            Color(red: 0.55, green: 0.35, blue: 0.15),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 18)
                .padding(.horizontal, avatarPadding)
                // Green overlay grows from left when player is winning
                .overlay(alignment: .leading) {
                    if ropeValue > 0 {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.green.opacity(0.35))
                            .frame(
                                width: CGFloat(ropeValue) * (containerWidth - 2 * avatarPadding) / 2,
                                height: 18
                            )
                            .padding(.leading, avatarPadding)
                    }
                }
                // Red overlay grows from right when CPU is winning
                .overlay(alignment: .trailing) {
                    if ropeValue < 0 {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.red.opacity(0.35))
                            .frame(
                                width: CGFloat(-ropeValue) * (containerWidth - 2 * avatarPadding) / 2,
                                height: 18
                            )
                            .padding(.trailing, avatarPadding)
                    }
                }

            // ── Centre flag ───────────────────────────────────────────────────
            // A thin red line marks "neutral" so kids can see how far they are
            // from the starting point.
            Rectangle()
                .fill(Color.red.opacity(0.8))
                .frame(width: 3, height: 36)

            // ── Knot ──────────────────────────────────────────────────────────
            // The knot slides left (player winning) or right (CPU winning).
            // It pulses larger when near an edge to signal danger.
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom)
                    )
                    .frame(width: 48, height: 48)
                    .shadow(color: .yellow.opacity(0.7), radius: 8)

                Text("🪢").font(.title2)
            }
            .scaleEffect(abs(ropeValue) > 0.75 ? 1.2 : 1.0)
            // offset(x:) moves the knot: positive = right, negative = left
            // Player winning (ropeValue > 0) moves knot LEFT (negative x)
            .offset(x: CGFloat(-ropeValue) * maxKnotOffset)
            .animation(.spring(response: 0.35, dampingFraction: 0.65), value: ropeValue)

            // ── Player avatar (left side) ─────────────────────────────────────
            Text(playerAvatar.emoji)
                .font(.system(size: 80))
                .scaleEffect(flashGreen ? 1.3 : 1.0)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 0)
                .animation(.spring(response: 0.25, dampingFraction: 0.4), value: flashGreen)

            // ── CPU avatar (right side) ───────────────────────────────────────
            Text(cpuAvatar.emoji)
                .font(.system(size: 80))
                .scaleEffect(flashRed ? 1.3 : 1.0)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 0)
                .animation(.spring(response: 0.25, dampingFraction: 0.4), value: flashRed)
        }
        .padding(.horizontal, 8)
    }
}


// MARK: - AnswerTile

/// One answer button in the 2×2 grid.
///
/// Colour rules:
///   Default          → white
///   Tapped + correct → green  (player pulls! 💪)
///   Tapped + wrong   → orange (oops — CPU counter-pulls)
///   Other buttons after tap → dimmed (disabled so no double-taps)
struct AnswerTile: View {
    let number: Int
    let selectedAnswer: Int?
    let correctAnswer: Int
    let action: () -> Void

    private var isSelected: Bool { selectedAnswer == number }
    private var isCorrect: Bool  { number == correctAnswer }
    private var isDimmed: Bool   { selectedAnswer != nil && !isSelected }

    private var tileColor: Color {
        guard isSelected else { return .white }
        return isCorrect ? .green : Color.orange.opacity(0.85)
    }

    var body: some View {
        Button(action: action) {
            Text("\(number)")
                .font(.system(size: 46, weight: .bold, design: .rounded))
                .foregroundColor(isSelected ? .white : .black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(tileColor)
                .cornerRadius(20)
                .shadow(
                    color: isSelected ? tileColor.opacity(0.5) : Color.black.opacity(0.15),
                    radius: isSelected ? 10 : 5,
                    y: 4
                )
                .opacity(isDimmed ? 0.4 : 1.0)
                .scaleEffect(isSelected ? 1.04 : 1.0)
        }
        .disabled(selectedAnswer != nil)
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isSelected)
    }
}


// MARK: - GameOverOverlay

/// Full-screen modal shown when the game ends.
///
/// WIN  → shows level complete banner + "Next Level" button
/// LOSS → shows encouragement + "Try Again" button (same level, no progress lost)
/// Both → show "Change Avatar" to return to the picker
struct GameOverOverlay: View {
    let playerWon: Bool
    let currentLevel: Int       // the level that just finished
    let playerAvatar: Avatar
    let cpuAvatar: Avatar
    let onNextLevel: () -> Void  // called on win — advances to next level
    let onRetry: () -> Void      // called on loss — retries the same level
    let onQuit: () -> Void

    @State private var scale: CGFloat = 0.4
    @State private var showConfetti = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()

            if showConfetti {
                ConfettiOverlay()
            }

            VStack(spacing: 28) {

                // ── Result banner ─────────────────────────────────────────────
                VStack(spacing: 12) {
                    if playerWon {
                        Text("🏆 LEVEL \(currentLevel) CLEAR! 🏆")
                            .font(.system(size: 34, weight: .black, design: .rounded))
                            .foregroundColor(.yellow)
                        Text("\(playerAvatar.emoji) pulled it all the way!")
                            .font(.title3)
                            .foregroundColor(.white.opacity(0.9))
                        // Preview of what's coming next
                        if currentLevel < 10 {
                            Text("Level \(currentLevel + 1) awaits... 🔥")
                                .font(.subheadline.bold())
                                .foregroundColor(.orange)
                        } else {
                            Text("You beat every level! 🌟")
                                .font(.subheadline.bold())
                                .foregroundColor(.orange)
                        }
                    } else {
                        Text("Great Try! 💪")
                            .font(.system(size: 38, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                        Text("\(cpuAvatar.emoji) was tough — you can do it!")
                            .font(.title3)
                            .foregroundColor(.white.opacity(0.9))
                            .multilineTextAlignment(.center)
                        Text("Level \(currentLevel) — try again")
                            .font(.subheadline.bold())
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

                // ── Action buttons ────────────────────────────────────────────
                VStack(spacing: 14) {
                    if playerWon {
                        // Win: advance forward
                        Button(action: onNextLevel) {
                            Label(
                                currentLevel < 10 ? "Next Level →" : "Play Level 10 Again",
                                systemImage: currentLevel < 10 ? "arrow.right.circle.fill" : "arrow.counterclockwise"
                            )
                            .font(.system(.title2, design: .rounded).bold())
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(colors: [.green, .teal], startPoint: .leading, endPoint: .trailing)
                            )
                            .cornerRadius(18)
                        }
                    } else {
                        // Loss: retry same level
                        Button(action: onRetry) {
                            Label("Try Again", systemImage: "arrow.counterclockwise")
                                .font(.system(.title2, design: .rounded).bold())
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    LinearGradient(colors: [.orange, .red], startPoint: .leading, endPoint: .trailing)
                                )
                                .cornerRadius(18)
                        }
                    }

                    Button(action: onQuit) {
                        Text("Change Avatar")
                            .font(.system(.body, design: .rounded).bold())
                            .foregroundColor(.white.opacity(0.85))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.white.opacity(0.15))
                            .cornerRadius(18)
                    }
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


// MARK: - ConfettiOverlay

/// Lightweight confetti that falls down the screen on a win.
/// Reuses the ConfettiPiece and ConfettiShape types from LevelUpCelebrationView.
struct ConfettiOverlay: View {
    @State private var pieces: [ConfettiPiece] = []

    var body: some View {
        ZStack {
            ForEach(pieces) { piece in
                ConfettiShape()
                    .fill(piece.color)
                    .frame(width: piece.size, height: piece.size)
                    .rotationEffect(.degrees(piece.rotation))
                    .position(piece.position)
                    .opacity(piece.opacity)
            }
        }
        .ignoresSafeArea()
        .onAppear { spawn() }
    }

    private func spawn() {
        let w = UIScreen.main.bounds.width
        let h = UIScreen.main.bounds.height

        pieces = (0..<55).map { _ in
            ConfettiPiece(
                position: CGPoint(x: CGFloat.random(in: 0...w), y: -20),
                color: [Color.red, .yellow, .green, .blue, .orange, .pink, .purple].randomElement()!,
                size: CGFloat.random(in: 8...16),
                rotation: Double.random(in: 0...360),
                opacity: 1.0
            )
        }

        for i in pieces.indices {
            let delay    = Double.random(in: 0...0.6)
            let duration = Double.random(in: 2.2...3.8)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeIn(duration: duration)) {
                    pieces[i].position.y = h + 30
                    pieces[i].rotation  += 540
                    pieces[i].opacity    = 0
                }
            }
        }
    }
}

#Preview {
    TugOfWarView(playerAvatar: Avatar.allAvatars[2], onQuit: {})
}
