import SwiftUI

// MARK: - Game Manager

class GameManager: ObservableObject {
    @Published var currentChallenge: MathChallenge
    @Published var showCelebration: Bool = false
    @Published var showEncouragement: Bool = false
    @Published var showLevelUpCelebration: Bool = false
    @Published var isCorrect: Bool = false
    @Published var selectedAnswer: Int? = nil
    @Published var characterEmotion: CharacterEmotion = .neutral
    @Published var gameState: GameState
    @Published var previousLevel: Int = 1
    
    private var adaptiveEngine: AdaptiveEngine
    private let audioManager = AudioManager()
    private let persistenceKey = "MathGoofGameState"
    
    enum CharacterEmotion {
        case neutral, happy, excited, thinking, sad, crying
    }
    
    init() {
        let saved = UserDefaults.standard.data(forKey: "MathGoofGameState")
            .flatMap { try? JSONDecoder().decode(GameState.self, from: $0) }
        
        let state = saved ?? GameState()
        self.gameState = state
        self.previousLevel = state.currentLevel
        self.adaptiveEngine = AdaptiveEngine(level: state.currentLevel)
        self.currentChallenge = adaptiveEngine.generateChallenge()
        adaptiveEngine.startTimer()
    }
    
    func checkAnswer(_ answer: Int) {
        guard selectedAnswer == nil else { return }
        selectedAnswer = answer
        let correct = answer == currentChallenge.correctAnswer
        isCorrect = correct
        
        let (up, down) = adaptiveEngine.recordAnswer(isCorrect: correct)
        
        if correct {
            characterEmotion = .excited
            showCelebration = true
            audioManager.playCorrect()
            gameState.lifetimeCorrect += 1
            
            if up {
                previousLevel = adaptiveEngine.currentLevel
                adaptiveEngine.adjustDifficulty(levelChange: 1)
                gameState.currentLevel = adaptiveEngine.currentLevel
                
                // Show level up celebration
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.showLevelUpCelebration = true
                    self.audioManager.playLevelUp()
                    self.audioManager.playApplause()
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                    self.showLevelUpCelebration = false
                    self.nextChallenge()
                }
            } else {
                saveState()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                    self.nextChallenge()
                }
            }
        } else {
            // Show sad or crying emotion based on streak
            characterEmotion = adaptiveEngine.currentLevel > 3 ? .crying : .sad
            showEncouragement = true
            audioManager.playIncorrect()
            
            if down {
                adaptiveEngine.adjustDifficulty(levelChange: -1)
                gameState.currentLevel = adaptiveEngine.currentLevel
            }
            
            saveState()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.selectedAnswer = nil
                self.showEncouragement = false
                self.characterEmotion = .neutral
            }
        }
    }
    
    func nextChallenge() {
        showCelebration = false
        selectedAnswer = nil
        characterEmotion = .neutral
        currentChallenge = adaptiveEngine.generateChallenge()
        adaptiveEngine.startTimer()
    }
    
    func changeCharacterColor(_ color: GameState.CharacterColor) {
        gameState.characterColor = color
        saveState()
    }
    
    private func saveState() {
        if let encoded = try? JSONEncoder().encode(gameState) {
            UserDefaults.standard.set(encoded, forKey: persistenceKey)
        }
    }
}
