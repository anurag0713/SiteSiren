import Foundation
import AVFoundation
import AppKit
import Combine
import os.log

@MainActor
public final class AudioManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published public private(set) var config: AudioConfig
    @Published public private(set) var isPlaying: Bool = false
    @Published public private(set) var audioStatusMessage: String? = nil
    
    private let logger = Logger(subsystem: AppConstants.appBundleIdentifier, category: "AudioManager")
    private var audioPlayer: AVAudioPlayer?
    private var lastTriggerTime: Date = .distantPast
    private var currentSecurityScopedURL: URL? = nil
    
    public override init() {
        self.config = SharedStore.shared.loadAudioConfig()
        super.init()
        validateAudioAvailability()
    }
    
    // MARK: - Configuration Updates
    
    public var currentAudioDisplayName: String {
        if let customName = config.customFileName, !customName.isEmpty {
            return customName
        }
        return "Default Siren (Built-in)"
    }
    
    public func setVolume(_ volume: Float) {
        config.volume = max(0.0, min(1.0, volume))
        audioPlayer?.volume = config.volume
        persistConfig()
    }
    
    public func setLoopAudio(_ loop: Bool) {
        config.loopAudio = loop
        audioPlayer?.numberOfLoops = loop ? -1 : 0
        persistConfig()
    }
    
    public func setCooldown(_ seconds: Double) {
        config.cooldownSeconds = max(0.5, seconds)
        persistConfig()
    }
    
    public func selectAudioFile(url: URL) {
        stopCurrentPlayback()
        
        do {
            // Create security-scoped bookmark
            let bookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            
            config.bookmarkData = bookmarkData
            config.customFileName = url.lastPathComponent
            persistConfig()
            
            audioStatusMessage = nil
            logger.info("Configured custom audio file: \(url.lastPathComponent)")
        } catch {
            logger.error("Failed to create security-scoped bookmark: \(error.localizedDescription)")
            audioStatusMessage = "Failed to save bookmark for selected file."
        }
    }
    
    public func resetToDefaultAudio() {
        stopCurrentPlayback()
        config.bookmarkData = nil
        config.customFileName = nil
        persistConfig()
        audioStatusMessage = nil
    }
    
    private func persistConfig() {
        SharedStore.shared.saveAudioConfig(config)
    }
    
    // MARK: - Audio Resolution
    
    private func resolveAudioURL() -> URL? {
        // Try security-scoped bookmark first
        if let bookmarkData = config.bookmarkData {
            var isStale = false
            do {
                let resolvedURL = try URL(
                    resolvingBookmarkData: bookmarkData,
                    options: .withSecurityScope,
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                
                if isStale {
                    logger.warning("Security-scoped bookmark is stale, re-saving...")
                    if let freshBookmark = try? resolvedURL.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                        config.bookmarkData = freshBookmark
                        persistConfig()
                    }
                }
                
                if FileManager.default.fileExists(atPath: resolvedURL.path) {
                    return resolvedURL
                } else {
                    logger.warning("Configured audio file no longer exists at: \(resolvedURL.path)")
                    audioStatusMessage = "Audio file unavailable"
                    return nil
                }
            } catch {
                logger.error("Error resolving bookmark: \(error.localizedDescription)")
                audioStatusMessage = "Audio file unavailable"
                return nil
            }
        }
        
        // Fallback to bundled sound
        if let bundledURL = Bundle.main.url(forResource: "DefaultAudio", withExtension: "aiff") {
            return bundledURL
        }
        
        return nil
    }
    
    public func validateAudioAvailability() {
        if config.bookmarkData != nil {
            if resolveAudioURL() == nil {
                audioStatusMessage = "Audio file unavailable"
            } else {
                audioStatusMessage = nil
            }
        } else {
            audioStatusMessage = nil
        }
    }
    
    // MARK: - Playback
    
    /// Triggered when a blocked domain is detected.
    /// Implements debouncing: ignores triggers within `cooldownSeconds`.
    public func handleBlockEvent(domain: String) {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastTriggerTime)
        
        // Debounce if within cooldown
        if elapsed < config.cooldownSeconds {
            logger.info("Blocked trigger for \(domain) suppressed (cooldown: \(elapsed)s < \(self.config.cooldownSeconds)s)")
            return
        }
        
        lastTriggerTime = now
        playAlert(isUserPreview: false)
    }
    
    /// Preview playback triggered directly from Settings UI.
    public func preview() {
        playAlert(isUserPreview: true)
    }
    
    public func stop() {
        stopCurrentPlayback()
    }
    
    private func playAlert(isUserPreview: Bool) {
        stopCurrentPlayback()
        
        guard let url = resolveAudioURL() else {
            logger.error("No valid audio file available to play alert.")
            audioStatusMessage = "Audio file unavailable"
            // Fallback system beep so the user still gets feedback
            NSSound.beep()
            return
        }
        
        let isSecurityScoped = config.bookmarkData != nil
        if isSecurityScoped {
            guard url.startAccessingSecurityScopedResource() else {
                logger.error("Failed to start accessing security-scoped resource at \(url.path)")
                audioStatusMessage = "Audio file unavailable"
                NSSound.beep()
                return
            }
            currentSecurityScopedURL = url
        }
        
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.volume = config.volume
            player.numberOfLoops = config.loopAudio ? -1 : 0
            player.currentTime = 0.0
            
            if player.play() {
                self.audioPlayer = player
                self.isPlaying = true
                self.audioStatusMessage = nil
                logger.info("Playing audio alert from \(url.lastPathComponent) (loop=\(self.config.loopAudio), vol=\(self.config.volume))")
            } else {
                logger.error("AVAudioPlayer failed to start playback.")
                stopCurrentPlayback()
            }
        } catch {
            logger.error("Failed to initialize AVAudioPlayer: \(error.localizedDescription)")
            audioStatusMessage = "Audio file unavailable"
            stopCurrentPlayback()
            NSSound.beep()
        }
    }
    
    private func stopCurrentPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        
        if let scopedURL = currentSecurityScopedURL {
            scopedURL.stopAccessingSecurityScopedResource()
            currentSecurityScopedURL = nil
        }
    }
    
    // MARK: - AVAudioPlayerDelegate
    
    public nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.stopCurrentPlayback()
        }
    }
    
    public nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            self.logger.error("Audio decode error: \(error?.localizedDescription ?? "unknown")")
            self.audioStatusMessage = "Audio file error"
            self.stopCurrentPlayback()
        }
    }
}
