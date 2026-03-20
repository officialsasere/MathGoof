import SwiftUI

// MARK: - AvatarPickerView.swift
// ─────────────────────────────────────────────────────────────────────────────
// Purpose: The "lobby" screen shown before a Tug of War match.
//
// The player scrolls through the avatar roster and taps one to select it.
// The CPU avatar is revealed with a dramatic random-pick animation to build
// excitement before the match starts.
//
// Navigation:
//   MathGoofApp  →  AvatarPickerView  →  TugOfWarView
// ─────────────────────────────────────────────────────────────────────────────

struct AvatarPickerView: View {

    @ObservedObject var profile: PlayerProfile
    let onStartGame: (Avatar) -> Void
    /// Feature 11: called when the player wants to start a 2-player match.
    /// MathGoofApp shows a second avatar picker for player 2.
    let onMultiplayer: (Avatar) -> Void

    // ── Local state ───────────────────────────────────────────────────────────

    /// Which avatar the player has tapped. Nil until they make a choice.
    @State private var selectedAvatar: Avatar? = nil

    /// Feature 6: controls the name-entry sheet for first-time players.
    @State private var showNameEntry: Bool = false
    @State private var pendingAvatar: Avatar? = nil   // avatar chosen before name entry

    /// Controls the reveal animation for the CPU avatar card.
    @State private var showCPUAvatar: Bool = false

    /// The CPU's randomly chosen avatar (set after player confirms selection).
    @State private var cpuAvatar: Avatar? = nil

    /// Drives the slot-machine spin animation for CPU avatar reveal.
    @State private var cpuRevealIndex: Int = 0

    /// Whether the "FIGHT!" button is visible (after CPU is revealed).
    @State private var showFightButton: Bool = false

    /// Timer that powers the slot-machine spinning effect.
    @State private var spinTimer: Timer? = nil

    var body: some View {
        ZStack {
            // ── Background ────────────────────────────────────────────────────
            LinearGradient(
                colors: [.blue.opacity(0.85), .purple.opacity(0.85)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {

                // ── Feature 6: Profile header ─────────────────────────────────
                ProfileHeader(profile: profile)
                    .padding(.top, 12)
                    .padding(.horizontal, 20)

                // ── Title ─────────────────────────────────────────────────────
                VStack(spacing: 6) {
                    Text("🪢 Tug of War")
                        .font(.system(size: 38, weight: .black, design: .rounded))
                        .foregroundColor(.white)

                    Text("Pick your fighter!")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.85))
                }
                .padding(.top, 4)

                // ── Avatar grid ───────────────────────────────────────────────
                // LazyVGrid creates a responsive 3-column grid.
                // "Lazy" means it only renders what's on screen — good for
                // performance if you ever expand to 20+ avatars.
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 16
                ) {
                    ForEach(Avatar.allAvatars) { avatar in
                        AvatarCard(
                            avatar: avatar,
                            isSelected: selectedAvatar?.id == avatar.id
                        ) {
                            // Haptic tap feedback — makes the tap feel physical
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            selectedAvatar = avatar

                            // Once player picks, immediately reveal the CPU
                            if showCPUAvatar == false {
                                revealCPUAvatar(excluding: avatar)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)

                // ── VS section ────────────────────────────────────────────────
                // Only visible after the player has chosen an avatar.
                if let player = selectedAvatar {
                    VSBanner(
                        playerAvatar: player,
                        cpuAvatar: showCPUAvatar ? cpuAvatar : nil,
                        spinningEmoji: showCPUAvatar ? nil : Avatar.allAvatars[cpuRevealIndex].emoji
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // ── Fight button ──────────────────────────────────────────────
                // Only appears after the CPU reveal animation finishes.
                if showFightButton, let player = selectedAvatar {
                    VStack(spacing: 12) {
                        // Solo vs CPU
                        Button {
                            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                            if profile.playerName.isEmpty {
                                pendingAvatar = player
                                showNameEntry = true
                            } else {
                                onStartGame(player)
                            }
                        } label: {
                            Label("⚡️ VS CPU", systemImage: "cpu")
                                .font(.system(size: 20, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    LinearGradient(colors: [.orange, .red],
                                                   startPoint: .leading, endPoint: .trailing)
                                )
                                .cornerRadius(18)
                                .shadow(color: .orange.opacity(0.6), radius: 10, y: 4)
                        }

                        // 2-Player pass-and-play
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            onMultiplayer(player)
                        } label: {
                            Label("👥 2 Players", systemImage: "person.2.fill")
                                .font(.system(size: 20, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    LinearGradient(colors: [.purple, .indigo],
                                                   startPoint: .leading, endPoint: .trailing)
                                )
                                .cornerRadius(18)
                        }
                    }
                    .padding(.horizontal, 40)
                    .transition(.scale.combined(with: .opacity))
                }

                Spacer()
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: selectedAvatar?.id)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: showFightButton)
        // Feature 6: name entry sheet on first launch
        .sheet(isPresented: $showNameEntry) {
            NameEntrySheet(profile: profile) {
                if let avatar = pendingAvatar {
                    onStartGame(avatar)
                }
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // revealCPUAvatar(excluding:)
    //
    // Creates a "slot machine" effect: rapidly cycles through avatars for
    // ~1.5 seconds, then lands on the CPU's final choice.
    //
    // Why this approach?
    //   Pure delight. Kids love the spinning reveal — it builds anticipation
    //   and makes the CPU feel like a real opponent being summoned.
    // ─────────────────────────────────────────────────────────────────────────
    private func revealCPUAvatar(excluding playerAvatar: Avatar) {
        showCPUAvatar = true

        // Pick the CPU's avatar now (but don't show it yet — let the spin play)
        let others = Avatar.allAvatars.filter { $0.id != playerAvatar.id }
        let chosen = others.randomElement() ?? Avatar.allAvatars[0]

        var spinCount = 0
        let totalSpins = 12

        // Fire a timer every 0.12s to flip the displayed avatar
        spinTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { timer in
            spinCount += 1
            cpuRevealIndex = (cpuRevealIndex + 1) % Avatar.allAvatars.count

            // Slow down near the end for dramatic effect
            if spinCount >= totalSpins - 3 {
                timer.invalidate()

                // Final reveal with a spring bounce
                withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                    cpuAvatar = chosen
                }

                // Show the fight button 0.5s after reveal settles
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation {
                        showFightButton = true
                    }
                    // Play a "ready" haptic
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            }
        }
    }
}


// MARK: - AvatarCard

/// A single selectable avatar tile in the picker grid.
///
/// Extracted into its own struct because it has its own animation state
/// (`wiggle`). Embedding this logic inside the parent would make the
/// parent massive and hard to read.
struct AvatarCard: View {
    let avatar: Avatar
    let isSelected: Bool
    let onTap: () -> Void

    @State private var wiggle: Bool = false

    var body: some View {
        Button(action: {
            onTap()
            // Wiggle the card when tapped for playful feedback
            withAnimation(.interpolatingSpring(stiffness: 500, damping: 10)) {
                wiggle = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                wiggle = false
            }
        }) {
            VStack(spacing: 8) {
                ZStack {
                    // Avatar background circle
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: avatar.colors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 72, height: 72)
                        .shadow(
                            color: isSelected ? avatar.colors[0].opacity(0.7) : .clear,
                            radius: 12
                        )

                    Text(avatar.emoji)
                        .font(.system(size: 36))

                    // Selection ring
                    if isSelected {
                        Circle()
                            .stroke(Color.white, lineWidth: 3)
                            .frame(width: 76, height: 76)
                    }
                }

                Text(avatar.name)
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .scaleEffect(wiggle ? 1.15 : (isSelected ? 1.08 : 1.0))
        .animation(.spring(response: 0.3, dampingFraction: 0.5), value: isSelected)
    }
}


// MARK: - VSBanner

/// The "Player VS CPU" comparison strip shown after the player picks.
/// Shows both avatars side by side with a glowing VS badge in the middle.
struct VSBanner: View {
    let playerAvatar: Avatar
    let cpuAvatar: Avatar?           // nil while CPU is still spinning
    let spinningEmoji: String?       // the emoji shown during the spin animation

    var body: some View {
        HStack(spacing: 0) {

            // ── Player side ───────────────────────────────────────────────────
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: playerAvatar.colors, startPoint: .top, endPoint: .bottom))
                        .frame(width: 70, height: 70)
                        .shadow(color: playerAvatar.colors[0].opacity(0.5), radius: 10)
                    Text(playerAvatar.emoji).font(.system(size: 34))
                }
                Text("YOU")
                    .font(.caption.bold())
                    .foregroundColor(.white.opacity(0.85))
            }

            Spacer()

            // ── VS badge ──────────────────────────────────────────────────────
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.orange, .red], startPoint: .top, endPoint: .bottom))
                    .frame(width: 48, height: 48)
                    .shadow(color: .orange.opacity(0.6), radius: 8)
                Text("VS")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundColor(.white)
            }

            Spacer()

            // ── CPU side ──────────────────────────────────────────────────────
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: cpuAvatar?.colors ?? [.gray, .gray.opacity(0.5)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 70, height: 70)
                        .shadow(color: (cpuAvatar?.colors[0] ?? .gray).opacity(0.5), radius: 10)

                    // Show the final CPU emoji OR the spinning one
                    Text(cpuAvatar?.emoji ?? spinningEmoji ?? "❓")
                        .font(.system(size: 34))
                }
                Text("CPU")
                    .font(.caption.bold())
                    .foregroundColor(.white.opacity(0.85))
            }
        }
        .padding(.horizontal, 50)
        .padding(.vertical, 16)
        .background(Color.white.opacity(0.1))
        .cornerRadius(20)
        .padding(.horizontal, 20)
    }
}



// MARK: - ProfileHeader  (Feature 6)

/// Compact strip shown at the top of the picker showing the player's
/// name, best level, and total stars. Motivates them to keep playing.
struct ProfileHeader: View {
    @ObservedObject var profile: PlayerProfile

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                if profile.playerName.isEmpty {
                    Text("Welcome, Player!")
                        .font(.system(.subheadline, design: .rounded).bold())
                        .foregroundColor(.white)
                } else {
                    Text("👋 \(profile.playerName)")
                        .font(.system(.subheadline, design: .rounded).bold())
                        .foregroundColor(.white)
                }
                if profile.bestLevel > 0 {
                    Text("Best: Level \(profile.bestLevel)")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
            }

            Spacer()

            // Star tally
            HStack(spacing: 4) {
                Image(systemName: "star.fill")
                    .foregroundColor(.yellow)
                    .font(.subheadline)
                Text("\(profile.totalStars)")
                    .font(.system(.subheadline, design: .rounded).bold())
                    .foregroundColor(.yellow)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.15))
            .cornerRadius(12)
        }
        .padding(.horizontal, 4)
    }
}


// MARK: - NameEntrySheet  (Feature 6)

/// Modal sheet shown on first launch. The player types their name and taps
/// "Let's Go!" — the name is saved to PlayerProfile and the game starts.
struct NameEntrySheet: View {
    @ObservedObject var profile: PlayerProfile
    let onDone: () -> Void

    @State private var name: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 28) {
            Text("What's your name?")
                .font(.system(size: 28, weight: .black, design: .rounded))
                .padding(.top, 40)

            Text("We'll track your stars and best level 🌟")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)

            TextField("Enter your name", text: $name)
                .font(.system(.title3, design: .rounded))
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(14)
                .padding(.horizontal, 30)

            Button {
                let trimmed = name.trimmingCharacters(in: .whitespaces)
                profile.setName(trimmed.isEmpty ? "Player" : trimmed)
                dismiss()
                onDone()
            } label: {
                Text("Let's Go! 🚀")
                    .font(.system(.title3, design: .rounded).bold())
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(LinearGradient(colors: [.orange, .red], startPoint: .leading, endPoint: .trailing))
                    .cornerRadius(16)
            }
            .padding(.horizontal, 30)

            Spacer()
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    AvatarPickerView(profile: PlayerProfile(), onStartGame: { _ in }, onMultiplayer: { _ in })
}
