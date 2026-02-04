import SwiftUI

struct CharacterView: View {
    let emotion: GameManager.CharacterEmotion
    let color: GameState.CharacterColor
    let isHappy: Bool
    
    @State private var bounce = false
    @State private var blink = false
    @State private var tearDrop = false
    
    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: color.gradient, startPoint: .top, endPoint: .bottom))
                .shadow(radius: 10)
            
            // Eyes
            HStack(spacing: 25) {
                EyeView(isClosed: blink, emotion: emotion)
                EyeView(isClosed: blink, emotion: emotion)
            }
            .offset(y: -10)
            
            // Mouth
            MouthView(emotion: emotion)
                .offset(y: 25)
            
            // Tears for crying emotion
            if emotion == .crying {
                TearsView(animate: tearDrop)
            }
        }
        .frame(width: 140, height: 140)
        .scaleEffect(bounce ? 1.2 : 1.0)
        .onChange(of: isHappy) { _, newValue in
            if newValue {
                withAnimation(.interpolatingSpring(stiffness: 300, damping: 10)) {
                    bounce = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    bounce = false
                }
            }
        }
        .onChange(of: emotion) { _, newValue in
            if newValue == .crying {
                tearDrop = true
            } else {
                tearDrop = false
            }
        }
        .onAppear {
            startBlinking()
        }
    }
    
    func startBlinking() {
        Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { _ in
            blink = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                blink = false
            }
        }
    }
}

struct EyeView: View {
    let isClosed: Bool
    let emotion: GameManager.CharacterEmotion
    
    var body: some View {
        if isClosed {
            Capsule()
                .fill(.black)
                .frame(width: 20, height: 4)
        } else {
            switch emotion {
            case .sad, .crying:
                // Sad eyes - slightly droopy
                Circle()
                    .fill(.white)
                    .frame(width: 20, height: 20)
                    .overlay(
                        Circle()
                            .fill(.black)
                            .frame(width: 8, height: 8)
                            .offset(y: 3)
                    )
            default:
                Circle()
                    .fill(.white)
                    .frame(width: 20, height: 20)
                    .overlay(Circle().fill(.black).frame(width: 8, height: 8))
            }
        }
    }
}

struct MouthView: View {
    let emotion: GameManager.CharacterEmotion
    
    var body: some View {
        switch emotion {
        case .happy, .excited:
            Circle()
                .trim(from: 0, to: 0.5)
                .stroke(.white, lineWidth: 6)
                .frame(width: 40)
                .rotationEffect(.degrees(0))
        case .thinking:
            Capsule()
                .fill(.white)
                .frame(width: 30, height: 6)
        case .sad, .crying:
            // Upside down smile (frown)
            Circle()
                .trim(from: 0, to: 0.5)
                .stroke(.white, lineWidth: 6)
                .frame(width: 40)
                .rotationEffect(.degrees(180))
        case .neutral:
            Capsule()
                .fill(.white)
                .frame(width: 20, height: 4)
        }
    }
}

struct TearsView: View {
    let animate: Bool
    @State private var offset1: CGFloat = 0
    @State private var offset2: CGFloat = 0
    @State private var opacity1: Double = 1
    @State private var opacity2: Double = 1
    
    var body: some View {
        ZStack {
            // Left tear
            Circle()
                .fill(.blue)
                .frame(width: 8, height: 8)
                .offset(x: -25, y: 10 + offset1)
                .opacity(opacity1)
            
            // Right tear
            Circle()
                .fill(.blue)
                .frame(width: 8, height: 8)
                .offset(x: 25, y: 10 + offset2)
                .opacity(opacity2)
        }
        .onAppear {
            if animate {
                animateTears()
            }
        }
        .onChange(of: animate) { _, newValue in
            if newValue {
                animateTears()
            } else {
                offset1 = 0
                offset2 = 0
                opacity1 = 1
                opacity2 = 1
            }
        }
    }
    
    func animateTears() {
        withAnimation(.easeIn(duration: 1.0).repeatForever(autoreverses: false)) {
            offset1 = 40
            opacity1 = 0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeIn(duration: 1.0).repeatForever(autoreverses: false)) {
                offset2 = 40
                opacity2 = 0
            }
        }
        
        // Reset tears periodically
        Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { _ in
            offset1 = 0
            opacity1 = 1
            offset2 = 0
            opacity2 = 1
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeIn(duration: 1.0)) {
                    offset1 = 40
                    opacity1 = 0
                }
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation(.easeIn(duration: 1.0)) {
                    offset2 = 40
                    opacity2 = 0
                }
            }
        }
    }
}

#Preview {
    VStack(spacing: 50) {
        CharacterView(emotion: .happy, color: .orange, isHappy: false)
        CharacterView(emotion: .sad, color: .blue, isHappy: false)
        CharacterView(emotion: .crying, color: .purple, isHappy: false)
    }
    .padding()
    .background(Color.blue.opacity(0.3))
}
