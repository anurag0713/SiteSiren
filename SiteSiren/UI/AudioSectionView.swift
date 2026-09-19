import SwiftUI
import AppKit
import UniformTypeIdentifiers

public struct AudioSectionView: View {
    @ObservedObject var audioManager: AudioManager
    
    public init(audioManager: AudioManager) {
        self.audioManager = audioManager
    }
    
    public var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Current Audio")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(audioManager.currentAudioDisplayName)
                                .font(.system(size: 14, weight: .semibold))
                        }
                        
                        Spacer()
                        
                        if audioManager.isPlaying {
                            Button(action: {
                                audioManager.stop()
                            }) {
                                Label("Stop", systemImage: "stop.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                        } else {
                            Button(action: {
                                audioManager.preview()
                            }) {
                                Label("Preview", systemImage: "play.fill")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    
                    HStack(spacing: 8) {
                        Button("Choose Audio File...") {
                            chooseAudioFile()
                        }
                        
                        if audioManager.config.bookmarkData != nil {
                            Button("Reset to Default Siren") {
                                audioManager.resetToDefaultAudio()
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.secondary)
                            .font(.caption)
                        }
                    }
                    
                    if let warning = audioManager.audioStatusMessage {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text(warning)
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Audio File")
            } footer: {
                Text("Supports audio and media formats: MP3, M4A, MP4, WAV, AIFF. Stored securely as a bookmark.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Volume:")
                        Spacer()
                        Text("\(Int(audioManager.config.volume * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Image(systemName: "speaker.fill")
                            .foregroundColor(.secondary)
                        Slider(
                            value: Binding(
                                get: { audioManager.config.volume },
                                set: { audioManager.setVolume($0) }
                            ),
                            in: 0.0...1.0
                        )
                        Image(systemName: "speaker.wave.3.fill")
                            .foregroundColor(.secondary)
                    }
                }
                
                Picker("Playback Mode", selection: Binding(
                    get: { audioManager.config.loopAudio },
                    set: { audioManager.setLoopAudio($0) }
                )) {
                    Text("Play Once").tag(false)
                    Text("Loop Continuously").tag(true)
                }
                .pickerStyle(.radioGroup)
                .padding(.vertical, 4)
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Cooldown between Triggers:")
                        Spacer()
                        Text("\(String(format: "%.1f", audioManager.config.cooldownSeconds)) seconds")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Slider(
                        value: Binding(
                            get: { audioManager.config.cooldownSeconds },
                            set: { audioManager.setCooldown($0) }
                        ),
                        in: 0.5...10.0,
                        step: 0.5
                    )
                }
                .padding(.vertical, 4)
            } header: {
                Text("Playback Settings")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
    
    private func chooseAudioFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        
        var audioTypes: [UTType] = [
            .audio,
            .mp3,
            .mpeg4Audio,
            .wav,
            .aiff,
            .mpeg4Movie,
            .quickTimeMovie,
            .movie
        ]
        if let mp4 = UTType(filenameExtension: "mp4") {
            audioTypes.append(mp4)
        }
        if let m4a = UTType(filenameExtension: "m4a") {
            audioTypes.append(m4a)
        }
        if let aac = UTType(filenameExtension: "aac") {
            audioTypes.append(aac)
        }
        panel.allowedContentTypes = audioTypes
        
        if panel.runModal() == .OK, let url = panel.url {
            audioManager.selectAudioFile(url: url)
        }
    }
}
