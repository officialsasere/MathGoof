
import SwiftUI

@main
struct MathGoofApp: App {
    @State private var showSplash = true
    
    var body: some Scene {
        WindowGroup {
            if showSplash {
                SplashScreenView(isPresented: $showSplash)
            } else {
                GameView()
            }
        }
    }
}
