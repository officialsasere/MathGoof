import SwiftUI

struct GameView: View {
    @StateObject private var game = GameManager()
    @State private var showColorPicker = false
    
    var body: some View {
        ZStack {
            BackgroundGradient()
                .ignoresSafeArea()
            
            VStack {
                // Header
                HStack {
                    Text("Level \(game.gameState.currentLevel)")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.8))
                    
                    Spacer()
                    
                    Button {
                        showColorPicker.toggle()
                    } label: {
                        Image(systemName: "paintpalette.fill")
                            .font(.title2)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .padding()

                Spacer()
                
                // Character
                CharacterView(
                    emotion: game.characterEmotion,
                    color: game.gameState.characterColor,
                    isHappy: game.showCelebration
                )
                .frame(height: 180)
                
                // Question
                Text(game.currentChallenge.questionText)
                    .font(.system(size: 64, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .padding()
                
                // Answer buttons
                VStack(spacing: 15) {
                    ForEach(game.currentChallenge.allAnswers, id: \.self) { answer in
                        AnswerButton(
                            answer: answer,
                            isSelected: game.selectedAnswer == answer,
                            isCorrect: game.isCorrect && game.selectedAnswer == answer,
                            action: { game.checkAnswer(answer) }
                        )
                    }
                }
                .padding(.horizontal, 40)
                
                Spacer()
            }
            
            // Overlays
            if game.showCelebration {
                CelebrationView()
            }
            
            if game.showEncouragement {
                EncouragementView()
            }
            
            if game.showLevelUpCelebration {
                LevelUpCelebrationView(newLevel: game.gameState.currentLevel)
            }
            
            if showColorPicker {
                ColorPickerSheet(
                    selectedColor: game.gameState.characterColor,
                    onSelect: { color in
                        game.changeCharacterColor(color)
                        showColorPicker = false
                    },
                    onDismiss: {
                        showColorPicker = false
                    }
                )
            }
        }
        .animation(.spring(), value: game.showCelebration)
        .animation(.spring(), value: game.showLevelUpCelebration)
    }
}

#Preview {
    GameView()
}
