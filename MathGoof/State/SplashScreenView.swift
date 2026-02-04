import SwiftUI

struct SplashScreenView: View {
    @Binding var isPresented: Bool
    @State private var scale: CGFloat = 0.5
    @State private var opacity: Double = 0
    @State private var rotation: Double = 0
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color.blue.opacity(0.8), Color.purple.opacity(0.8)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 30) {
                // Animated character
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [.orange, .yellow],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                        .shadow(radius: 20)
                        .frame(width: 150, height: 150)
                    
                    // Happy face
                    VStack(spacing: 10) {
                        HStack(spacing: 25) {
                            Circle()
                                .fill(.white)
                                .frame(width: 20, height: 20)
                                .overlay(Circle().fill(.black).frame(width: 8, height: 8))
                            Circle()
                                .fill(.white)
                                .frame(width: 20, height: 20)
                                .overlay(Circle().fill(.black).frame(width: 8, height: 8))
                        }
                        .offset(y: -10)
                        
                        Circle()
                            .trim(from: 0, to: 0.5)
                            .stroke(.white, lineWidth: 6)
                            .frame(width: 40)
                            .rotationEffect(.degrees(0))
                            .offset(y: 10)
                    }
                }
                .scaleEffect(scale)
                .rotationEffect(.degrees(rotation))
                
                // App title
                VStack(spacing: 10) {
                    Text("Math Goof")
                        .font(.system(size: 50, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text("Let's Learn & Have Fun!")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.9))
                }
                .opacity(opacity)
            }
        }
        .onAppear {
            // Animate the character
            withAnimation(.spring(response: 0.8, dampingFraction: 0.6)) {
                scale = 1.0
            }
            
            withAnimation(.easeIn(duration: 0.6)) {
                opacity = 1.0
            }
            
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                rotation = 5
            }
            
            // Dismiss splash screen after 2.5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation {
                    isPresented = false
                }
            }
        }
    }
}

#Preview {
    SplashScreenView(isPresented: .constant(true))
}
