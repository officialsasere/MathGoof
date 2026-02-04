import SwiftUI

struct LevelUpCelebrationView: View {
    let newLevel: Int
    @State private var confettiPieces: [ConfettiPiece] = []
    @State private var scale: CGFloat = 0.5
    @State private var opacity: Double = 0
    
    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.7)
                .ignoresSafeArea()
            
            // Confetti
            ForEach(confettiPieces) { piece in
                ConfettiShape()
                    .fill(piece.color)
                    .frame(width: piece.size, height: piece.size)
                    .rotationEffect(.degrees(piece.rotation))
                    .position(piece.position)
                    .opacity(piece.opacity)
            }
            
            // Main celebration content
            VStack(spacing: 30) {
                // Trophy or star icon
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [.yellow, .orange],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                        .frame(width: 120, height: 120)
                        .shadow(color: .yellow, radius: 20)
                    
                    Image(systemName: "star.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.white)
                        .rotationEffect(.degrees(360 * scale))
                }
                .scaleEffect(scale)
                
                VStack(spacing: 10) {
                    Text("🎉 LEVEL UP! 🎉")
                        .font(.system(size: 40, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text("You reached Level \(newLevel)!")
                        .font(.title2.bold())
                        .foregroundColor(.yellow)
                    
                    Text("Keep up the amazing work!")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.9))
                }
                .opacity(opacity)
            }
            .padding(40)
        }
        .onAppear {
            createConfetti()
            animateCelebration()
        }
    }
    
    func createConfetti() {
        for _ in 0..<50 {
            let piece = ConfettiPiece(
                position: CGPoint(
                    x: CGFloat.random(in: 0...UIScreen.main.bounds.width),
                    y: -50
                ),
                color: [.red, .blue, .green, .yellow, .purple, .orange, .pink].randomElement()!,
                size: CGFloat.random(in: 8...15),
                rotation: Double.random(in: 0...360),
                opacity: 1.0
            )
            confettiPieces.append(piece)
        }
        
        animateConfetti()
    }
    
    func animateConfetti() {
        for index in confettiPieces.indices {
            let delay = Double.random(in: 0...0.5)
            let duration = Double.random(in: 2...4)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeIn(duration: duration)) {
                    confettiPieces[index].position.y = UIScreen.main.bounds.height + 50
                    confettiPieces[index].rotation += 720
                    confettiPieces[index].opacity = 0
                }
            }
        }
    }
    
    func animateCelebration() {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) {
            scale = 1.0
        }
        
        withAnimation(.easeIn(duration: 0.4)) {
            opacity = 1.0
        }
    }
}

struct ConfettiPiece: Identifiable {
    let id = UUID()
    var position: CGPoint
    let color: Color
    let size: CGFloat
    var rotation: Double
    var opacity: Double
}

struct ConfettiShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        // Create a star or square shape
        if Bool.random() {
            // Star
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX + rect.width * 0.2, y: rect.midY - rect.height * 0.1))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.midX + rect.width * 0.2, y: rect.midY + rect.height * 0.1))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.midX - rect.width * 0.2, y: rect.midY + rect.height * 0.1))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.midX - rect.width * 0.2, y: rect.midY - rect.height * 0.1))
            path.closeSubpath()
        } else {
            // Rectangle
            path.addRect(rect)
        }
        
        return path
    }
}

#Preview {
    LevelUpCelebrationView(newLevel: 5)
}
