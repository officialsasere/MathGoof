import SwiftUI

// MARK: - LevelMapView.swift
// ─────────────────────────────────────────────────────────────────────────────
// Purpose: The world map screen shown after the player picks an avatar.
//   Displays 10 level nodes arranged in a winding path. Each node shows the
//   player's best star rating for that level. Tapping an unlocked node starts
//   that specific level.
//
// Navigation:
//   AvatarPickerView → LevelMapView → TugOfWarView (at chosen level)
//
// Unlock rules:
//   Level 1 is always unlocked.
//   Level N is unlocked when the player has beaten level N-1 at least once
//   (i.e. profile.bestLevel >= N-1).
//   This means a player who has never played can only start level 1.
//
// Layout:
//   The 10 nodes are arranged in two columns that alternate left/right
//   to create a winding "path" feel — similar to Candy Crush or Duolingo.
//   A connecting line is drawn between each consecutive pair of nodes.
// ─────────────────────────────────────────────────────────────────────────────

struct LevelMapView: View {

    @ObservedObject var profile: PlayerProfile
    let playerAvatar: Avatar
    let onSelectLevel: (Int) -> Void    // called with the chosen level number
    let onDailyChallenge: () -> Void    // called when the daily button is tapped
    let onQuit: () -> Void              // back to avatar picker

    // Layout constants
    private let nodeSize: CGFloat   = 72
    private let columnSpacing: CGFloat = 140
    private let rowSpacing: CGFloat    = 90

    // The winding path: alternates left (false) and right (true)
    // Index 0 = level 1 (bottom of screen), index 9 = level 10 (top)
    private let rightColumn = [false, true, true, false, false, true, true, false, false, true]

    var body: some View {
        ZStack {
            // ── Background ────────────────────────────────────────────────────
            LinearGradient(
                colors: [.indigo.opacity(0.9), .purple.opacity(0.85), .blue.opacity(0.9)],
                startPoint: .bottom,
                endPoint: .top
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {

                // ── Header ────────────────────────────────────────────────────
                HStack {
                    Button(action: onQuit) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                            Text("Avatars")
                        }
                        .font(.system(.subheadline, design: .rounded).bold())
                        .foregroundColor(.white.opacity(0.8))
                    }

                    Spacer()

                    VStack(spacing: 2) {
                        Text("World Map")
                            .font(.system(.title2, design: .rounded).bold())
                            .foregroundColor(.white)
                        Text(profile.displayStars)
                            .font(.caption.bold())
                            .foregroundColor(.yellow)
                    }

                    Spacer()

                    // Player avatar badge
                    Text(playerAvatar.emoji)
                        .font(.title2)
                        .frame(width: 40)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)

                // ── Daily Challenge banner ────────────────────────────────────
                DailyChallengeBanner(
                    profile: profile,
                    onTap: onDailyChallenge
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

                // ── Level path (scrollable) ───────────────────────────────────
                // Reversed so level 10 appears at the top and level 1 at the bottom
                ScrollView(showsIndicators: false) {
                    ScrollViewReader { proxy in
                        ZStack {
                            // Draw connecting lines first (below nodes)
                            LevelPathLines(
                                rightColumn:   rightColumn,
                                nodeSize:      nodeSize,
                                columnSpacing: columnSpacing,
                                rowSpacing:    rowSpacing,
                                profile:       profile
                            )

                            // Draw level nodes on top
                            VStack(spacing: rowSpacing - nodeSize) {
                                ForEach((1...10).reversed(), id: \.self) { level in
                                    HStack {
                                        // Alternate which side each node is on
                                        let isRight = rightColumn[level - 1]

                                        if isRight { Spacer() }

                                        LevelNode(
                                            level:     level,
                                            stars:     profile.stars(for: level),
                                            isUnlocked: level <= profile.bestLevel + 1,
                                            isCurrent:  level == profile.bestLevel + 1
                                        ) {
                                            onSelectLevel(level)
                                        }
                                        .frame(width: nodeSize, height: nodeSize)
                                        .id(level)

                                        if !isRight { Spacer() }
                                    }
                                    .padding(.horizontal, (UIScreen.main.bounds.width - columnSpacing * 2) / 2)
                                }
                            }
                            .padding(.vertical, 20)
                        }
                        .onAppear {
                            // Scroll to the current level so player sees where they are
                            let target = max(1, profile.bestLevel + 1)
                            withAnimation { proxy.scrollTo(target, anchor: .center) }
                        }
                    }
                }
            }
        }
    }
}


// MARK: - LevelNode

/// A single level button on the map.
/// Shows the level number, star rating, and visual locked/unlocked state.
struct LevelNode: View {
    let level: Int
    let stars: Int          // 0 = not beaten, 1–3 = best result
    let isUnlocked: Bool
    let isCurrent: Bool     // true = the next level to beat (pulsing)
    let onTap: () -> Void

    @State private var pulse = false

    var body: some View {
        Button(action: {
            guard isUnlocked else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onTap()
        }) {
            ZStack {
                // Background circle
                Circle()
                    .fill(
                        isUnlocked
                            ? LinearGradient(
                                colors: stars > 0
                                    ? [.green, .teal]
                                    : isCurrent ? [.orange, .yellow] : [.blue, .indigo],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                              )
                            : LinearGradient(colors: [.gray.opacity(0.5), .gray.opacity(0.3)],
                                             startPoint: .top, endPoint: .bottom)
                    )
                    .shadow(
                        color: isCurrent ? .orange.opacity(0.7) : .black.opacity(0.3),
                        radius: isCurrent ? 12 : 4
                    )

                if isUnlocked {
                    VStack(spacing: 2) {
                        Text("\(level)")
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundColor(.white)

                        // Show stars if beaten, arrow if it's the next level
                        if stars > 0 {
                            HStack(spacing: 1) {
                                ForEach(1...3, id: \.self) { i in
                                    Image(systemName: i <= stars ? "star.fill" : "star")
                                        .font(.system(size: 8))
                                        .foregroundColor(i <= stars ? .yellow : .white.opacity(0.4))
                                }
                            }
                        } else if isCurrent {
                            Image(systemName: "play.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }
                } else {
                    // Locked
                    Image(systemName: "lock.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
        }
        .disabled(!isUnlocked)
        // Pulse animation for the current level only
        .scaleEffect(pulse ? 1.08 : 1.0)
        .onAppear {
            guard isCurrent else { return }
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}


// MARK: - LevelPathLines

/// Draws the connecting lines between consecutive level nodes.
/// A line is green if the lower level has been beaten, grey otherwise.
struct LevelPathLines: View {
    let rightColumn: [Bool]
    let nodeSize: CGFloat
    let columnSpacing: CGFloat
    let rowSpacing: CGFloat
    let profile: PlayerProfile

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let cx = w / 2  // horizontal centre

            Canvas { ctx, size in
                // Node centres — match the VStack layout (reversed, level 10 at top)
                var centres: [CGPoint] = []
                for i in 0..<10 {
                    let level  = 10 - i          // level 10 first, level 1 last
                    let isRight = rightColumn[level - 1]
                    let x = isRight ? cx + columnSpacing / 2 : cx - columnSpacing / 2
                    let y = CGFloat(i) * rowSpacing + nodeSize / 2 + 20
                    centres.append(CGPoint(x: x, y: y))
                }

                // Draw a line between each consecutive pair
                for i in 0..<(centres.count - 1) {
                    let from = centres[i]
                    let to   = centres[i + 1]
                    let levelBeaten = (10 - i) <= profile.bestLevel

                    var path = Path()
                    path.move(to: from)

                    // Curved bezier control point between the two nodes
                    let mid = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
                    let ctrl = CGPoint(x: mid.x, y: from.y)
                    path.addQuadCurve(to: to, control: ctrl)

                    ctx.stroke(
                        path,
                        with: .color(levelBeaten ? .green.opacity(0.6) : .white.opacity(0.2)),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round, dash: levelBeaten ? [] : [8, 6])
                    )
                }
            }
        }
    }
}


// MARK: - DailyChallengeBanner

/// A compact banner showing today's daily challenge status.
/// Glows gold if not yet played today, greyed out if already completed.
struct DailyChallengeBanner: View {
    @ObservedObject var profile: PlayerProfile
    let onTap: () -> Void

    private var alreadyPlayed: Bool { profile.dailyChallengePlayedToday }

    var body: some View {
        Button(action: {
            guard !alreadyPlayed else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onTap()
        }) {
            HStack(spacing: 12) {
                Text("☀️")
                    .font(.title2)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Daily Challenge")
                        .font(.system(.subheadline, design: .rounded).bold())
                        .foregroundColor(.white)
                    Text(alreadyPlayed ? "Come back tomorrow!" : "New challenge available!")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.75))
                }

                Spacer()

                if alreadyPlayed {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title3)
                } else {
                    Text("PLAY")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundColor(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.yellow)
                        .cornerRadius(10)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                alreadyPlayed
                    ? LinearGradient(colors: [.white.opacity(0.08), .white.opacity(0.08)],
                                     startPoint: .leading, endPoint: .trailing)
                    : LinearGradient(colors: [.orange.opacity(0.4), .yellow.opacity(0.3)],
                                     startPoint: .leading, endPoint: .trailing)
            )
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(alreadyPlayed ? Color.clear : Color.yellow.opacity(0.5), lineWidth: 1.5)
            )
        }
        .disabled(alreadyPlayed)
    }
}

#Preview {
    LevelMapView(
        profile: PlayerProfile(),
        playerAvatar: Avatar.allAvatars[0],
        onSelectLevel: { _ in },
        onDailyChallenge: {},
        onQuit: {}
    )
}
