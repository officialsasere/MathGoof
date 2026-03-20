import SwiftUI

// MARK: - MathGoofApp.swift
// ─────────────────────────────────────────────────────────────────────────────
// App navigation state machine. Every screen transition lives here.
//
// Screens and flow:
//   Splash → AvatarPickerView (player 1)
//               ├─ VS CPU     → LevelMapView → TugOfWarView
//               ├─ Daily      → DailyChallengeView
//               └─ 2 Players  → AvatarPickerView (player 2) → MultiplayerView
// ─────────────────────────────────────────────────────────────────────────────

@main
struct MathGoofApp: App {

    @State private var showSplash = true
    @StateObject private var profile = PlayerProfile()

    // MARK: - Navigation state

    /// The avatar player 1 chose. Non-nil = show level map.
    @State private var player1Avatar: Avatar? = nil

    /// Set when a level is chosen from the map. Non-nil = show TugOfWarView.
    @State private var selectedLevel: Int? = nil

    /// Set when "Daily Challenge" is tapped.
    @State private var showDaily = false

    /// Set when "2 Players" is tapped — holds player 1's avatar.
    /// Non-nil = show the second avatar picker for player 2.
    @State private var multiplayerPlayer1: Avatar? = nil

    /// Set when player 2 picks their avatar. Non-nil = show MultiplayerView.
    @State private var multiplayerPlayer2: Avatar? = nil

    var body: some Scene {
        WindowGroup {
            ZStack {
                content
                if showSplash {
                    SplashScreenView(isPresented: $showSplash)
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .animation(.easeInOut(duration: 0.35), value: showSplash)
        }
    }

    // MARK: - Content router

    @ViewBuilder
    private var content: some View {

        // ── Multiplayer: both avatars chosen ──────────────────────────────────
        if let p1 = multiplayerPlayer1, let p2 = multiplayerPlayer2 {
            MultiplayerView(player1: p1, player2: p2) {
                withAnimation { multiplayerPlayer2 = nil }
            }

        // ── Multiplayer: picking player 2's avatar ────────────────────────────
        } else if let p1 = multiplayerPlayer1 {
            // Reuse AvatarPickerView with a custom title for player 2
            Player2PickerView(player1Avatar: p1) { p2 in
                withAnimation { multiplayerPlayer2 = p2 }
            } onQuit: {
                withAnimation { multiplayerPlayer1 = nil }
            }

        // ── Daily challenge ───────────────────────────────────────────────────
        } else if showDaily, let avatar = player1Avatar {
            DailyChallengeView(profile: profile, playerAvatar: avatar) {
                withAnimation { showDaily = false }
            }

        // ── Solo: battle screen ───────────────────────────────────────────────
        } else if let avatar = player1Avatar, let level = selectedLevel {
            TugOfWarView(playerAvatar: avatar, startLevel: level, profile: profile) {
                withAnimation { selectedLevel = nil }
            }
            .id("battle-\(level)")  // .id forces full recreate at each new level

        // ── Solo: level map ───────────────────────────────────────────────────
        } else if let avatar = player1Avatar {
            LevelMapView(
                profile: profile,
                playerAvatar: avatar,
                onSelectLevel: { level in
                    withAnimation { selectedLevel = level }
                },
                onDailyChallenge: {
                    withAnimation { showDaily = true }
                },
                onQuit: {
                    withAnimation { player1Avatar = nil }
                }
            )

        // ── Avatar picker (player 1 / solo) ───────────────────────────────────
        } else if !showSplash {
            AvatarPickerView(profile: profile) { chosen in
                withAnimation { player1Avatar = chosen }
            } onMultiplayer: { chosen in
                withAnimation { multiplayerPlayer1 = chosen }
            }
        }
    }
}


// MARK: - Player2PickerView

/// A thin wrapper around AvatarPickerView shown when picking player 2's avatar
/// in multiplayer mode. Shows a different title so the context is clear.
struct Player2PickerView: View {
    let player1Avatar: Avatar
    let onSelect: (Avatar) -> Void
    let onQuit: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.red.opacity(0.85), .purple.opacity(0.9)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                HStack {
                    Button(action: onQuit) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .font(.system(.subheadline, design: .rounded).bold())
                        .foregroundColor(.white.opacity(0.8))
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                VStack(spacing: 6) {
                    Text("👥 Player 2")
                        .font(.system(size: 36, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    Text("Pick your fighter!")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.85))
                }

                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 16
                ) {
                    ForEach(Avatar.allAvatars.filter { $0.id != player1Avatar.id }) { avatar in
                        AvatarCard(avatar: avatar, isSelected: false) {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            onSelect(avatar)
                        }
                    }
                }
                .padding(.horizontal, 20)

                Spacer()
            }
        }
    }
}
