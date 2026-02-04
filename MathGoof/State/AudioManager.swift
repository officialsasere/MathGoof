import AVFoundation
import SwiftUI

// MARK: - Audio Manager

class AudioManager: ObservableObject {
    private var audioPlayer: AVAudioPlayer?
    
    func playCorrect() {
        AudioServicesPlaySystemSound(1103)
    }
    
    func playIncorrect() {
        AudioServicesPlaySystemSound(1053)
    }
    
    func playCelebration() {
        // Play a more celebratory sound
        AudioServicesPlaySystemSound(1025)
    }
    
    func playLevelUp() {
        // Play triumphant sound for level completion
        AudioServicesPlaySystemSound(1013) // Success sound
        
        // Add haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        // Play again after a short delay for emphasis
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            AudioServicesPlaySystemSound(1025)
        }
    }
    
    func playApplause() {
        // For now using system sounds, but you can add custom audio files
        // To add custom sounds:
        // 1. Add .mp3 or .wav files to your project
        // 2. Use AVAudioPlayer to play them
        
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        // Multiple haptic feedbacks to simulate applause
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            generator.notificationOccurred(.success)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            generator.notificationOccurred(.success)
        }
    }
}
