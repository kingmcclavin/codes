import UIKit
import AVFoundation

/// Haptics plus tiny synthesized sound effects (no audio files needed).
final class Feedback {
    static let shared = Feedback()

    var hapticsOn = true
    var soundOn = true

    enum Sound: CaseIterable {
        case tick
        case swing
        case hit
        case putt
        case land
        case splash
        case cup
        case perfect
        case coin
        case reveal
    }

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var buffers: [Sound: AVAudioPCMBuffer] = [:]
    private var nextPlayer = 0
    private var audioReady = false
    private let sampleRate = 44_100.0

    private init() {
        setUpAudio()
    }

    // MARK: Haptics

    func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        guard hapticsOn else { return }
        let g = UIImpactFeedbackGenerator(style: style)
        g.impactOccurred()
    }

    func success() {
        guard hapticsOn else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    func warning() {
        guard hapticsOn else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    // MARK: Sound

    func play(_ sound: Sound) {
        guard soundOn, audioReady, let buffer = buffers[sound], !players.isEmpty else { return }
        if !engine.isRunning {
            try? engine.start()
        }
        let p = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        p.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        if !p.isPlaying { p.play() }
    }

    private func setUpAudio() {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return }
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        for _ in 0..<5 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: format)
            players.append(p)
        }
        engine.mainMixerNode.outputVolume = 0.6
        for s in Sound.allCases {
            buffers[s] = makeBuffer(s, format: format)
        }
        do {
            try engine.start()
            audioReady = true
        } catch {
            audioReady = false
        }
    }

    private func makeBuffer(_ s: Sound, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let duration: Double
        switch s {
        case .tick: duration = 0.04
        case .swing: duration = 0.28
        case .hit: duration = 0.12
        case .putt: duration = 0.08
        case .land: duration = 0.1
        case .splash: duration = 0.5
        case .cup: duration = 0.45
        case .perfect: duration = 0.45
        case .coin: duration = 0.3
        case .reveal: duration = 0.5
        }
        let frames = AVAudioFrameCount(duration * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let data = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        var seed: UInt32 = 12345
        func noise() -> Float {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return Float(seed >> 8) / Float(1 << 24) * 2 - 1
        }
        let n = Int(frames)
        for i in 0..<n {
            let t = Double(i) / sampleRate
            let p = Double(i) / Double(n)
            let w = 2 * Double.pi * t
            let decay = 1 - p
            var v: Double = 0
            switch s {
            case .tick:
                v = sin(w * 1800) * decay
            case .swing:
                v = Double(noise()) * sin(Double.pi * p) * 0.5
            case .hit:
                let body = sin(w * 210) * 0.8 + Double(noise()) * 0.5
                v = body * pow(decay, 4)
            case .putt:
                v = sin(w * 520) * pow(decay, 5)
            case .land:
                v = Double(noise()) * pow(decay, 3) * 0.5
            case .splash:
                let wobble = 0.6 + 0.4 * sin(w * 18)
                v = Double(noise()) * pow(decay, 2) * 0.6 * wobble
            case .cup:
                let f = p < 0.3 ? 880.0 : 1320.0
                v = sin(w * f) * pow(decay, 2) * 0.6
            case .perfect:
                let f = 660.0 + 660.0 * p
                v = sin(w * f) * decay * 0.5
            case .coin:
                let f = p < 0.35 ? 988.0 : 1319.0
                v = sin(w * f) * decay * 0.45
            case .reveal:
                let chord = sin(w * 523) + sin(w * 659) + sin(w * 784)
                v = chord / 3 * decay * 0.6
            }
            data[i] = Float(v)
        }
        return buffer
    }
}
