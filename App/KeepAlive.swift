// Background audio loop and screen dimming to prevent iOS from sleeping.
import UIKit
import AVFoundation
#if canImport(ExVaultCore)
import ExVaultCore
#endif

final class KeepAlive {
    private var audioPlayer: AVAudioPlayer?
    private var dimOverlayView: UIView?
    private var originalBrightness: CGFloat = 0.5
    private(set) var isDimmed = false

    func start() {
        if Thread.isMainThread {
            UIApplication.shared.isIdleTimerDisabled = true
        } else {
            DispatchQueue.main.async {
                UIApplication.shared.isIdleTimerDisabled = true
            }
        }
        startSilentAudio()
        setupNotifications()
    }

    func stop() {
        if Thread.isMainThread {
            UIApplication.shared.isIdleTimerDisabled = false
            self.setDim(false)
        } else {
            DispatchQueue.main.async {
                UIApplication.shared.isIdleTimerDisabled = false
                self.setDim(false)
            }
        }
        audioPlayer?.stop()
        audioPlayer = nil
    }

    func setDim(_ on: Bool) {
        let block = {
            guard self.isDimmed != on else { return }
            self.isDimmed = on

            if on {
                self.originalBrightness = UIScreen.main.brightness
                UIScreen.main.brightness = 0.0

                if self.dimOverlayView == nil, let window = UIApplication.shared.keyWindow {
                    let overlay = UIView(frame: window.bounds)
                    overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                    overlay.backgroundColor = .black
                    overlay.isUserInteractionEnabled = true

                    let tap = UITapGestureRecognizer(target: self, action: #selector(self.handleDimTap))
                    overlay.addGestureRecognizer(tap)

                    window.addSubview(overlay)
                    self.dimOverlayView = overlay
                }
            } else {
                UIScreen.main.brightness = max(0.2, self.originalBrightness)
                self.dimOverlayView?.removeFromSuperview()
                self.dimOverlayView = nil
            }
        }

        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }

    @objc private func handleDimTap() {
        setDim(false)
    }

    private func startSilentAudio() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)

            let wavData = SilentWav.make(seconds: 1)
            let player = try AVAudioPlayer(data: wavData)
            player.numberOfLoops = -1
            player.volume = 0.01 // Minimal non-zero volume so iOS does not suspend the audio session
            player.prepareToPlay()
            player.play()
            self.audioPlayer = player
        } catch {
            Log.error("KeepAlive audio player error: \(error)")
        }
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        if type == .ended {
            try? AVAudioSession.sharedInstance().setActive(true)
            audioPlayer?.play()
        }
    }

    @objc private func handleAppDidBecomeActive() {
        if let player = audioPlayer, !player.isPlaying {
            try? AVAudioSession.sharedInstance().setActive(true)
            player.play()
        }
    }
}
