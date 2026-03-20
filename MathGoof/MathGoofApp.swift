import SwiftUI

// MARK: - MathGoofApp.swift
// ─────────────────────────────────────────────────────────────────────────────
// Purpose: The app's root entry point and top-level navigation controller.
//
// All navigation state lives HERE — no individual screen knows about any
// other screen. They just call callback closures and the app root decides
// what to show next. This pattern is called "lifting state up".
//
// App flow:
//   SplashScreenView  (auto-dismisses after 2.5s)
//       ↓
//   AvatarPickerView  (player picks their fighter)
//       ↓
//   TugOfWarView      (the battle!)
//       ↓ onQuit callback
//   AvatarPickerView  (returns here for a rematch with a different avatar)
// ─────────────────────────────────────────────────────────────────────────────

@main
struct MathGoofApp: App {

    /// When true, the splash screen covers everything else.
    @State private var showSplash = true

    /// Set when the player picks an avatar. Nil = show the picker.
    /// Non-nil = show the battle screen with this avatar.
    @State private var selectedAvatar: Avatar? = nil

    var body: some Scene {
        WindowGroup {
            ZStack {

                // ── Content layer ─────────────────────────────────────────────
                // Only one branch is active at a time.
                if let avatar = selectedAvatar {
                    // Battle screen — player has chosen their fighter
                    TugOfWarView(playerAvatar: avatar) {
                        // onQuit: clear the avatar to return to picker
                        withAnimation(.easeInOut(duration: 0.3)) {
                            selectedAvatar = nil
                        }
                    }
                } else if !showSplash {
                    // Avatar picker — shown after splash dismisses
                    AvatarPickerView { chosenAvatar in
                        withAnimation(.easeInOut(duration: 0.3)) {
                            selectedAvatar = chosenAvatar
                        }
                    }
                }

                // ── Splash overlay ────────────────────────────────────────────
                // ZStack ordering: this sits ON TOP of the content layer.
                // Once showSplash = false it fades away via .transition(.opacity).
                if showSplash {
                    SplashScreenView(isPresented: $showSplash)
                        .transition(.opacity)
                        .zIndex(1)   // Explicit z-ordering ensures splash is always on top
                }
            }
            .animation(.easeInOut(duration: 0.35), value: showSplash)
            .animation(.easeInOut(duration: 0.3),  value: selectedAvatar?.id)
        }
    }
}
