import SwiftUI
import QuartzCore

@MainActor
class RopePhysicsEngine: ObservableObject {
    @Published var position: Double = 0.0          // -1.0 = full CPU win    +1.0 = full player win
    @Published var isNearEdge: Bool = false

    private var displayLink: CADisplayLink?
    private var lastUpdateTime: CFTimeInterval = 0

    // ── Tune these values ────────────────────────────────────────────────
    var cpuDriftSpeed: Double = 0.06              // units per second (idle pull toward CPU)
    var levelDriftMultiplier: Double = 1.0         // increases with level

    var correctPullStrength: Double = 0.40         // big instant reward
    var wrongAnswerPenalty: Double = 0.08         // punish mistakes

    func start() {
        stop()
        displayLink = CADisplayLink(target: self, selector: #selector(updatePhysics))
        displayLink?.preferredFramesPerSecond = 60
        displayLink?.add(to: .main, forMode: .default)
        lastUpdateTime = CACurrentMediaTime()
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func updatePhysics() {
        let now = CACurrentMediaTime()
        let deltaTime = now - lastUpdateTime
        lastUpdateTime = now

        // Continuous passive drift toward CPU
        let driftThisFrame = cpuDriftSpeed * levelDriftMultiplier * deltaTime
        position -= driftThisFrame

        // Clamp
        position = max(-1.0, min(1.0, position))

        // Tension feedback
        isNearEdge = abs(position) > 0.82

        objectWillChange.send()
    }

    func applyCorrectAnswer() {
        position += correctPullStrength
        position = min(1.0, position)
    }

    func applyWrongAnswer() {
        position -= wrongAnswerPenalty
        position = max(-1.0, position)
    }

    func reset() {
        position = 0.0
    }

    deinit {
        // Because CADisplayLink is independent of this object, there is no
        // retain cycle. The engine's ref count reaches zero normally, and
        // deinit is called on whichever thread releases the last reference.
        //
        // We only need to nil out the displayLink here — we cannot
        // call stop() directly because stop() is @MainActor-isolated and
        // deinit is nonisolated in Swift 5.9.
        //
        // This is safe because invalidate() on CADisplayLink is thread-safe
        // (documented by Apple), and setting pointers to nil is always safe.
        displayLink?.invalidate()
        displayLink = nil
    }
}
