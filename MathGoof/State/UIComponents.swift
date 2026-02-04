import SwiftUI

// MARK: - Background Gradient

struct BackgroundGradient: View {
    var body: some View {
        LinearGradient(
            colors: [Color.blue.opacity(0.8), Color.purple.opacity(0.8)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Answer Button

struct AnswerButton: View {
    let answer: Int
    let isSelected: Bool
    let isCorrect: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text("\(answer)")
                .font(.system(.title, design: .rounded).bold())
                .frame(maxWidth: .infinity)
                .padding()
                .background(backgroundColor)
                .foregroundColor(isSelected ? .white : .black)
                .cornerRadius(15)
                .shadow(radius: 5)
        }
        .disabled(isSelected)
    }
    
    var backgroundColor: Color {
        if isSelected {
            return isCorrect ? Color.green : Color.red
        }
        return Color.white
    }
}

// MARK: - Celebration View

struct CelebrationView: View {
    @State private var scale: CGFloat = 0.5
    
    var body: some View {
        VStack {
            Text("✨ EXCELLENT! ✨")
                .font(.largeTitle.bold())
                .foregroundColor(.yellow)
                .shadow(radius: 10)
                .scaleEffect(scale)
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                scale = 1.2
            }
            
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                scale = 1.0
            }
        }
    }
}

// MARK: - Encouragement View

struct EncouragementView: View {
    @State private var scale: CGFloat = 0.5
    
    let encouragingMessages = [
        "Try again! You've got this!",
        "Keep trying! You're learning!",
        "Almost there! Don't give up!",
        "That's okay! Let's try another!",
        "You're doing great! Keep going!"
    ]
    
    var body: some View {
        VStack(spacing: 20) {
            Text("😢")
                .font(.system(size: 60))
            
            Text(encouragingMessages.randomElement() ?? "Keep trying!")
                .font(.title.bold())
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .scaleEffect(scale)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                scale = 1.0
            }
        }
    }
}

// MARK: - Color Picker Sheet

struct ColorPickerSheet: View {
    let selectedColor: GameState.CharacterColor
    let onSelect: (GameState.CharacterColor) -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    onDismiss()
                }
            
            VStack {
                Spacer()
                
                VStack(spacing: 20) {
                    Text("Pick a Color")
                        .font(.headline)
                        .padding(.top)
                    
                    HStack(spacing: 20) {
                        ForEach(GameState.CharacterColor.allCases, id: \.self) { color in
                            ColorCircle(
                                color: color,
                                isSelected: selectedColor == color,
                                action: { onSelect(color) }
                            )
                        }
                    }
                    .padding()
                    
                    Button("Close") {
                        onDismiss()
                    }
                    .padding(.bottom)
                }
                .background(Color.white)
                .cornerRadius(20)
                .padding()
            }
        }
    }
}

struct ColorCircle: View {
    let color: GameState.CharacterColor
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: color.gradient,
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 50, height: 50)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: isSelected ? 4 : 0)
                )
                .shadow(radius: 5)
        }
    }
}

#Preview("Background") {
    BackgroundGradient()
}

#Preview("Celebration") {
    ZStack {
        Color.blue.opacity(0.3)
        CelebrationView()
    }
}

#Preview("Encouragement") {
    ZStack {
        Color.blue.opacity(0.3)
        EncouragementView()
    }
}

#Preview("Color Picker") {
    ColorPickerSheet(
        selectedColor: .orange,
        onSelect: { _ in },
        onDismiss: {}
    )
}
