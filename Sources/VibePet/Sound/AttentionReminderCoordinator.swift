import Foundation

final class AttentionReminderCoordinator {
    private weak var sessionStore: SessionStore?
    private var statusObserver: Any?
    private var defaultsObserver: Any?
    private var pulseTimer: Timer?
    private var pendingStartWorkItem: DispatchWorkItem?
    private var scheduledCadence: AttentionReminderSoundCadence?

    func start(sessionStore: SessionStore) {
        self.sessionStore = sessionStore

        if statusObserver == nil {
            statusObserver = NotificationCenter.default.addObserver(
                forName: .sessionStatusChanged,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.evaluateLoopState()
            }
        }

        if defaultsObserver == nil {
            defaultsObserver = NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.evaluateLoopState()
            }
        }

        evaluateLoopState()
    }

    func stop() {
        if let statusObserver {
            NotificationCenter.default.removeObserver(statusObserver)
            self.statusObserver = nil
        }
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
            self.defaultsObserver = nil
        }

        pendingStartWorkItem?.cancel()
        pendingStartWorkItem = nil
        pulseTimer?.invalidate()
        pulseTimer = nil
        scheduledCadence = nil
    }

    private func evaluateLoopState() {
        guard shouldPlayAttentionReminder else {
            stopScheduledPlayback()
            return
        }

        let cadence = AttentionAnimationPreferences.resolvedSoundCadence()
        if scheduledCadence != cadence {
            stopScheduledPlayback()
        }

        guard pulseTimer == nil, pendingStartWorkItem == nil else { return }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingStartWorkItem = nil
            self.playAlignedPulse()

            let timer = Timer(timeInterval: cadence.interval, repeats: true) { [weak self] _ in
                self?.playAlignedPulse()
            }
            self.pulseTimer = timer
            self.scheduledCadence = cadence
            RunLoop.main.add(timer, forMode: .common)
        }

        scheduledCadence = cadence
        pendingStartWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + alignedStartDelay(), execute: workItem)
    }

    private func playAlignedPulse() {
        guard shouldPlayAttentionReminder else {
            stopScheduledPlayback()
            return
        }

        SoundManager.shared.playStrongAttention(for: AttentionAnimationPreferences.resolvedVariant())
    }

    private func alignedStartDelay() -> TimeInterval {
        let cycleDuration = AttentionAnimationPreferences.cycleDuration
        let elapsedInCycle = Date().timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: cycleDuration)
        let remainder = cycleDuration - elapsedInCycle
        return remainder < 0.02 ? 0 : remainder
    }

    private var shouldPlayAttentionReminder: Bool {
        guard let sessionStore else { return false }
        guard sessionStore.hasSessionNeedingAttention else { return false }
        guard AttentionAnimationPreferences.resolvedVariant() != .subtle else { return false }
        return AttentionAnimationPreferences.resolvedSoundEnabled()
    }

    private func stopScheduledPlayback() {
        pendingStartWorkItem?.cancel()
        pendingStartWorkItem = nil
        pulseTimer?.invalidate()
        pulseTimer = nil
        scheduledCadence = nil
    }
}
