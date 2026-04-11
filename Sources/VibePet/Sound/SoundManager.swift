import Foundation
import AVFoundation

enum SoundEvent: String, CaseIterable {
    case sessionStart
    case taskComplete
    case needsAttention
    case error
    case sessionEnd
}

final class SoundManager {
    static let shared = SoundManager()

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var buffers: [SoundEvent: AVAudioPCMBuffer] = [:]
    private var strongAttentionBuffers: [AttentionAnimationVariant: AVAudioPCMBuffer] = [:]
    private var isReady = false
    private var outputFormat: AVAudioFormat?

    private init() {
        setupEngine()
        generateBuiltInSounds()
    }

    private func setupEngine() {
        engine.attach(playerNode)

        // Use the mixer's output format so buffers match
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        outputFormat = format
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)

        startEngine()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEngineConfigChange),
            name: .AVAudioEngineConfigurationChange,
            object: engine
        )
    }

    private func startEngine() {
        do {
            try engine.start()
            isReady = true
        } catch {
            isReady = false
            print("[VibePet] Audio engine failed to start: \(error)")
        }
    }

    @objc private func handleEngineConfigChange(_ notification: Notification) {
        isReady = false
        startEngine()
    }

    func play(_ event: SoundEvent) {
        DispatchQueue.main.async { [self] in
            if !engine.isRunning { startEngine() }
            guard isReady, let buffer = buffers[event] else { return }
            playerNode.stop()
            playerNode.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
            playerNode.play()
        }
    }

    func playStrongAttention(for variant: AttentionAnimationVariant) {
        DispatchQueue.main.async { [self] in
            guard isReady else { return }

            let resolvedVariant: AttentionAnimationVariant = variant == .subtle
                ? AttentionAnimationPreferences.defaultStrongStyle
                : variant
            guard let buffer = strongAttentionBuffers[resolvedVariant] else { return }

            playerNode.stop()
            playerNode.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
            playerNode.play()
        }
    }

    // MARK: - Procedural chiptune sound generation

    private func generateBuiltInSounds() {
        guard let format = outputFormat else { return }
        let sampleRate = format.sampleRate
        let channels = Int(format.channelCount)

        buffers[.sessionStart] = generateToneSequence(
            frequencies: [523.25, 659.25, 783.99],
            durations: [0.08, 0.08, 0.12],
            sampleRate: sampleRate,
            channels: channels,
            format: format,
            waveform: .square
        )

        buffers[.taskComplete] = generateToneSequence(
            frequencies: [783.99, 1046.50],
            durations: [0.1, 0.15],
            sampleRate: sampleRate,
            channels: channels,
            format: format,
            waveform: .square
        )

        buffers[.needsAttention] = generateToneSequence(
            frequencies: [880.0, 0, 880.0, 0, 880.0],
            durations: [0.06, 0.04, 0.06, 0.04, 0.08],
            sampleRate: sampleRate,
            channels: channels,
            format: format,
            waveform: .square
        )

        buffers[.error] = generateToneSequence(
            frequencies: [659.25, 523.25],
            durations: [0.1, 0.15],
            sampleRate: sampleRate,
            channels: channels,
            format: format,
            waveform: .sawtooth
        )

        buffers[.sessionEnd] = generateToneSequence(
            frequencies: [523.25, 392.0, 329.63],
            durations: [0.08, 0.08, 0.12],
            sampleRate: sampleRate,
            channels: channels,
            format: format,
            waveform: .triangle
        )

        strongAttentionBuffers[.urgentPulse] = generateToneSequence(
            frequencies: [988.0, 0, 988.0, 0, 1318.51],
            durations: [0.045, 0.04, 0.05, 0.16, 0.1],
            sampleRate: sampleRate,
            channels: channels,
            format: format,
            waveform: .square,
            volume: 0.11
        )

        strongAttentionBuffers[.goldenAlert] = generateToneSequence(
            frequencies: [1046.50, 1318.51, 1567.98, 0, 1318.51],
            durations: [0.04, 0.045, 0.08, 0.05, 0.08],
            sampleRate: sampleRate,
            channels: channels,
            format: format,
            waveform: .triangle,
            volume: 0.1
        )

        strongAttentionBuffers[.hyperRipple] = generateToneSequence(
            frequencies: [739.99, 880.0, 1046.50, 1174.66],
            durations: [0.04, 0.04, 0.045, 0.05],
            sampleRate: sampleRate,
            channels: channels,
            format: format,
            waveform: .square,
            volume: 0.085
        )

        strongAttentionBuffers[.attentionShake] = generateToneSequence(
            frequencies: [784.0, 659.25, 784.0, 659.25],
            durations: [0.05, 0.05, 0.05, 0.07],
            sampleRate: sampleRate,
            channels: channels,
            format: format,
            waveform: .sawtooth,
            volume: 0.095
        )
    }

    private enum Waveform {
        case square, triangle, sawtooth
    }

    private func generateToneSequence(
        frequencies: [Double],
        durations: [Double],
        sampleRate: Double,
        channels: Int,
        format: AVAudioFormat,
        waveform: Waveform,
        volume: Float = 0.15
    ) -> AVAudioPCMBuffer? {
        let totalDuration = durations.reduce(0, +)
        let frameCount = AVAudioFrameCount(totalDuration * sampleRate)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }

        buffer.frameLength = frameCount
        guard let channelData = buffer.floatChannelData else { return nil }

        var sampleIndex: AVAudioFrameCount = 0

        for (i, freq) in frequencies.enumerated() {
            let duration = durations[i]
            let samples = AVAudioFrameCount(duration * sampleRate)

            for j in 0..<samples {
                guard sampleIndex < frameCount else { break }

                let t = Double(j) / sampleRate
                let phase = freq * t
                var sample: Float = 0

                if freq > 0 {
                    switch waveform {
                    case .square:
                        sample = sin(2.0 * .pi * phase) >= 0 ? volume : -volume
                    case .triangle:
                        let p = phase.truncatingRemainder(dividingBy: 1.0)
                        sample = volume * Float(4.0 * abs(p - 0.5) - 1.0)
                    case .sawtooth:
                        let p = phase.truncatingRemainder(dividingBy: 1.0)
                        sample = volume * Float(2.0 * p - 1.0)
                    }

                    // Apply envelope (fade in/out)
                    let fadeLen = min(0.005, duration / 4)
                    let fadeSamples = Int(fadeLen * sampleRate)
                    if j < fadeSamples {
                        sample *= Float(j) / Float(fadeSamples)
                    } else if j > samples - AVAudioFrameCount(fadeSamples) {
                        let remaining = Float(samples - j)
                        sample *= remaining / Float(fadeSamples)
                    }
                }

                // Write same sample to all channels (mono content, multi-channel buffer)
                for ch in 0..<channels {
                    channelData[ch][Int(sampleIndex)] = sample
                }
                sampleIndex += 1
            }
        }

        return buffer
    }
}
