import SwiftUI
import Combine

// MARK: - MultiplayerView.swift
// ─────────────────────────────────────────────────────────────────────────────
// Purpose: Local pass-and-play multiplayer for 2 players on one device.
//
// How it works:
//   Players take turns answering math questions. A correct answer pulls the
//   rope toward that player's side. A wrong answer gives the opponent a
//   small advantage. The first player to pull the rope all the way wins.
//
//   The game pauses between turns and shows a "Hand the device to Player 2"
//   screen so each player only sees their own question.
//
// Architecture:
//   MultiplayerState owns all game logic (same pattern as TugOfWarState).
//   MultiplayerView is purely a display layer.
//
// Turn structure:
//   Each turn = one question. After the player answers (right or wrong),
//   the turn ends and a handoff screen appears before the next question.
//   This prevents the current player from seeing the next player's question.
// ─────────────────────────────────────────────────────────────────────────────


// MARK: - MultiplayerState

@MainActor
class MultiplayerState: ObservableObject {

    // MARK: - Published

    @Published var player1Avatar: Avatar
    @Published var player2Avatar: Avatar

    /// Whose turn it is. Starts with player 1.
    @Published var currentPlayer: Int = 1    // 1 or 2

    /// The question for the current player's turn.
    @Published var currentChallenge: MathChallenge

    /// Which answer the current player tapped. Nil = waiting.
    @Published var selectedAnswer: Int? = nil

    /// True after an answer is tapped — shows result briefly before handoff.
    @Published var showingResult: Bool = false

    /// Whether the last answer was correct.
    @Published var lastAnswerCorrect: Bool = false

    /// True = show the "Hand the device to Player X" screen between turns.
    @Published var showHandoff: Bool = false

    /// True when someone has won.
    @Published var gameOver: Bool = false

    /// Rope position. Positive = Player 1 winning, Negative = Player 2 winning.
    let rope = RopePhysicsEngine()

    /// Flash states for each player's avatar.
    @Published var flashPlayer1: Bool = false
    @Published var flashPlayer2: Bool = false

    // MARK: - Private

    private var adaptiveEngine: AdaptiveEngine
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Computed

    /// The winning player number (1 or 2). Only valid when gameOver = true.
    var winningPlayer: Int { rope.position >= 1.0 ? 1 : 2 }

    var currentAvatar: Avatar { currentPlayer == 1 ? player1Avatar : player2Avatar }
    var waitingAvatar: Avatar { currentPlayer == 1 ? player2Avatar : player1Avatar }

    // MARK: - Init

    init(player1: Avatar, player2: Avatar) {
        self.player1Avatar = player1
        self.player2Avatar = player2
        self.adaptiveEngine = AdaptiveEngine(level: 3)   // multiplayer starts at level 3
        self.currentChallenge = adaptiveEngine.generateChallenge()

        // Multiplayer rope has NO passive CPU drift — it only moves on answers.
        // Both players are fighting each other, not a computer.
        rope.$position
            .receive(on: RunLoop.main)
            .sink { [weak self] position in
                guard let self, !self.gameOver else { return }
                if abs(position) >= 1.0 {
                    self.gameOver = true
                    self.rope.stop()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Start

    func start() {
        // No CPU drift in multiplayer — cpuDriftSpeed = 0
        rope.cpuDriftSpeed = 0.0
        rope.start()
        adaptiveEngine.startTimer()
    }

    // MARK: - Answer

    /// Called when the current player taps an answer.
    func answer(_ tappedAnswer: Int) {
        guard selectedAnswer == nil, !gameOver else { return }

        let responseTime = adaptiveEngine.stopTimer()
        selectedAnswer   = tappedAnswer
        lastAnswerCorrect = (tappedAnswer == currentChallenge.correctAnswer)
        showingResult     = true

        let (shouldLevelUp, shouldLevelDown) = adaptiveEngine.recordAnswer(isCorrect: lastAnswerCorrect)

        if lastAnswerCorrect {
            // Pull toward the current player's side
            rope.correctPullStrength = responseTime < 2.0 ? 0.45 : 0.30
            if currentPlayer == 1 {
                rope.applyCorrectAnswer()      // moves position toward +1.0
                flashPlayer1 = true
            } else {
                // Player 2 pulls toward -1.0 (flip direction)
                rope.position -= rope.correctPullStrength
                rope.position = max(-1.0, rope.position)
                flashPlayer2 = true
            }
            if shouldLevelUp { adaptiveEngine.adjustDifficulty(levelChange: +1) }
        } else {
            // Wrong: small penalty toward opponent's side
            if currentPlayer == 1 {
                rope.position -= 0.08    // moves toward player 2
                flashPlayer2 = true      // opponent's avatar reacts
            } else {
                rope.position += 0.08    // moves toward player 1
                flashPlayer1 = true
            }
            rope.position = max(-1.0, min(1.0, rope.position))
            if shouldLevelDown { adaptiveEngine.adjustDifficulty(levelChange: -1) }
        }

        if gameOver { return }

        // Show result for 0.8s, then handoff screen
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self, !self.gameOver else { return }
            self.flashPlayer1 = false
            self.flashPlayer2 = false
            self.showHandoff  = true
        }
    }

    // MARK: - Handoff confirmed

    /// Called when the handoff screen is dismissed (player taps "Ready").
    /// Switches to the next player and loads a new question.
    func confirmHandoff() {
        currentPlayer     = currentPlayer == 1 ? 2 : 1
        selectedAnswer    = nil
        showingResult     = false
        showHandoff       = false
        currentChallenge  = adaptiveEngine.generateChallenge()
        adaptiveEngine.startTimer()
    }

    // MARK: - New game

    func newGame() {
        rope.stop()
        rope.reset()
        rope.cpuDriftSpeed = 0.0
        rope.start()

        currentPlayer     = 1
        selectedAnswer    = nil
        showingResult     = false
        showHandoff       = false
        gameOver          = false
        flashPlayer1      = false
        flashPlayer2      = false

        adaptiveEngine    = AdaptiveEngine(level: 3)
        currentChallenge  = adaptiveEngine.generateChallenge()
        adaptiveEngine.startTimer()
    }

    deinit {
        MainActor.assumeIsolated { rope.stop() }
    }
}


// MARK: - MultiplayerView

struct MultiplayerView: View {

    let player1Avatar: Avatar
    let player2Avatar: Avatar
    let onQuit: () -> Void

    @StateObject private var game: MultiplayerState
    @StateObject private var audio = TugAudioManager()

    init(player1: Avatar, player2: Avatar, onQuit: @escaping () -> Void) {
        _game = StateObject(wrappedValue: MultiplayerState(player1: player1, player2: player2))
        self.player1Avatar = player1
        self.player2Avatar = player2
        self.onQuit = onQuit
    }

    var body: some View {
        ZStack {
            // Background shifts colour based on whose turn it is
            LinearGradient(
                colors: game.currentPlayer == 1
                    ? [.blue.opacity(0.9), .indigo.opacity(0.9)]
                    : [.red.opacity(0.85), .purple.opacity(0.9)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.5), value: game.currentPlayer)

            VStack(spacing: 16) {

                // ── Player indicators ─────────────────────────────────────────
                MultiplayerTopBar(
                    player1Avatar: game.player1Avatar,
                    player2Avatar: game.player2Avatar,
                    currentPlayer: game.currentPlayer,
                    onQuit: onQuit
                )
                .padding(.horizontal, 20)
                .padding(.top, 8)

                // ── Rope ──────────────────────────────────────────────────────
                GeometryReader { geo in
                    RopeArena(
                        playerAvatar: game.player1Avatar,
                        cpuAvatar: game.player2Avatar,
                        ropeValue: game.rope.position,
                        flashGreen: game.flashPlayer1,
                        flashRed: game.flashPlayer2,
                        containerWidth: geo.size.width,
                        cpuMood: .neutral
                    )
                }
                .frame(height: 160)

                // ── Whose turn banner ─────────────────────────────────────────
                HStack(spacing: 10) {
                    Text(game.currentAvatar.emoji)
                        .font(.title2)
                    Text("Player \(game.currentPlayer)'s Turn")
                        .font(.system(.title3, design: .rounded).bold())
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.15))
                .cornerRadius(20)

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
                            audio.playCorrectPull()
                            game.answer(num)
                        }
                    }
                }
                .padding(.horizontal, 24)

                Spacer(minLength: 0)
            }

            // ── Handoff screen ────────────────────────────────────────────────
            if game.showHandoff {
                HandoffScreen(
                    nextPlayer: game.currentPlayer == 1 ? 2 : 1,
                    nextAvatar: game.waitingAvatar,
                    onReady: { game.confirmHandoff() }
                )
                .transition(.opacity)
            }

            // ── Game over ─────────────────────────────────────────────────────
            if game.gameOver {
                MultiplayerGameOverOverlay(
                    winningPlayer: game.winningPlayer,
                    winnerAvatar: game.winningPlayer == 1 ? game.player1Avatar : game.player2Avatar,
                    onPlayAgain: {
                        game.newGame()
                        audio.playMatchStart()
                    },
                    onQuit: onQuit
                )
                .transition(.opacity)
            }
        }
        .onAppear {
            game.start()
            audio.playMatchStart()
        }
        .onChange(of: game.gameOver) { _, isOver in
            if isOver { audio.playPlayerWins() }
        }
        .animation(.easeInOut(duration: 0.3), value: game.showHandoff)
        .animation(.easeInOut(duration: 0.3), value: game.gameOver)
    }
}


// MARK: - MultiplayerTopBar

/// Shows both player avatars with an indicator of whose turn it is.
struct MultiplayerTopBar: View {
    let player1Avatar: Avatar
    let player2Avatar: Avatar
    let currentPlayer: Int
    let onQuit: () -> Void

    var body: some View {
        HStack {
            // Player 1 indicator
            HStack(spacing: 6) {
                Text(player1Avatar.emoji).font(.title2)
                Text("P1")
                    .font(.system(.caption, design: .rounded).bold())
                    .foregroundColor(currentPlayer == 1 ? .yellow : .white.opacity(0.4))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(currentPlayer == 1 ? Color.white.opacity(0.25) : Color.clear)
            .cornerRadius(12)
            .animation(.spring(response: 0.3), value: currentPlayer)

            Spacer()

            Button(action: onQuit) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.6))
            }

            Spacer()

            // Player 2 indicator
            HStack(spacing: 6) {
                Text("P2")
                    .font(.system(.caption, design: .rounded).bold())
                    .foregroundColor(currentPlayer == 2 ? .yellow : .white.opacity(0.4))
                Text(player2Avatar.emoji).font(.title2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(currentPlayer == 2 ? Color.white.opacity(0.25) : Color.clear)
            .cornerRadius(12)
            .animation(.spring(response: 0.3), value: currentPlayer)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.white.opacity(0.1))
        .cornerRadius(16)
    }
}


// MARK: - HandoffScreen

/// Full-screen cover shown between turns.
/// Hides the current question from the player whose turn it is NOT.
/// The next player taps "I'm Ready" to reveal their question.
struct HandoffScreen: View {
    let nextPlayer: Int
    let nextAvatar: Avatar
    let onReady: () -> Void

    @State private var scale: CGFloat = 0.85

    var body: some View {
        ZStack {
            Color.black.opacity(0.88).ignoresSafeArea()

            VStack(spacing: 32) {
                // Big avatar
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: nextAvatar.colors,
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                        .frame(width: 110, height: 110)
                        .shadow(color: nextAvatar.colors[0].opacity(0.5), radius: 16)
                    Text(nextAvatar.emoji)
                        .font(.system(size: 56))
                }

                VStack(spacing: 10) {
                    Text("Hand it to Player \(nextPlayer)!")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)

                    Text("Don't let Player \(nextPlayer == 1 ? 2 : 1) peek 👀")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.7))
                }

                Button(action: onReady) {
                    HStack {
                        Text(nextAvatar.emoji)
                        Text("I'm Ready!")
                            .font(.system(.title2, design: .rounded).bold())
                        Text(nextAvatar.emoji)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        LinearGradient(
                            colors: nextAvatar.colors,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(20)
                    .shadow(color: nextAvatar.colors[0].opacity(0.5), radius: 10)
                }
                .padding(.horizontal, 36)
            }
            .scaleEffect(scale)
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) {
                scale = 1.0
            }
        }
    }
}


// MARK: - MultiplayerGameOverOverlay

struct MultiplayerGameOverOverlay: View {
    let winningPlayer: Int
    let winnerAvatar: Avatar
    let onPlayAgain: () -> Void
    let onQuit: () -> Void

    @State private var scale: CGFloat = 0.4
    @State private var showConfetti = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.75).ignoresSafeArea()

            if showConfetti { ConfettiOverlay() }

            VStack(spacing: 28) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: winnerAvatar.colors,
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: 100, height: 100)
                        .shadow(color: winnerAvatar.colors[0].opacity(0.6), radius: 16)
                    Text(winnerAvatar.emoji)
                        .font(.system(size: 50))
                }

                VStack(spacing: 10) {
                    Text("🏆 Player \(winningPlayer) Wins! 🏆")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundColor(.yellow)

                    Text("\(winnerAvatar.name) pulled it all the way!")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                }

                VStack(spacing: 14) {
                    Button(action: onPlayAgain) {
                        Label("Play Again", systemImage: "arrow.counterclockwise")
                            .font(.system(.title2, design: .rounded).bold())
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(LinearGradient(colors: [.orange, .red],
                                                       startPoint: .leading, endPoint: .trailing))
                            .cornerRadius(18)
                    }

                    Button(action: onQuit) {
                        Text("Change Avatars")
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { showConfetti = true }
        }
    }
}
