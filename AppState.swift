import AVFoundation
import Foundation
import MediaPlayer

@MainActor
final class AppState: ObservableObject {
    @Published var account: Account?
    @Published var searchResults: [Track] = []
    @Published var homeTracks: [Track] = []
    @Published var playlists: [Playlist] = []
    @Published var likedTracks: [Track] = []
    @Published var recentTracks: [Track] = []
    @Published var collectedPlaylists: [Playlist] = []
    @Published var selectedPlaylistTracks: [Track] = []
    @Published var activeTrack: Track?
    @Published var isPlaying = false
    @Published var isPreview = false
    @Published var isBusy = false
    @Published var errorMessage: String?
    @Published var protectedTrack: Track?
    @Published var showingPlayer = false

    private let service = QishuiService.shared
    private var player: AVPlayer?
    private var finishedObserver: NSObjectProtocol?

    init() {
        account = service.account
        do { try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default) }
        catch { errorMessage = error.localizedDescription }
        MPRemoteCommandCenter.shared().playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }
        MPRemoteCommandCenter.shared().pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
    }

    func search(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { searchResults = []; return }
        isBusy = true
        defer { isBusy = false }
        do { searchResults = try await service.search(trimmed) }
        catch { errorMessage = error.localizedDescription }
    }

    func loadHome() async {
        guard homeTracks.isEmpty else { return }
        do { homeTracks = try await service.search("热门音乐") }
        catch { errorMessage = error.localizedDescription }
    }

    func loadLibrary() async {
        guard account != nil else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            playlists = try await service.playlists().filter { $0.type != 1 }
            likedTracks = try await service.likedTracks()
            recentTracks = try await service.recentTracks()
            collectedPlaylists = try await service.collectedPlaylists()
        } catch { errorMessage = error.localizedDescription }
    }

    func loadPlaylist(_ playlist: Playlist) async {
        isBusy = true
        defer { isBusy = false }
        do { selectedPlaylistTracks = try await service.playlistTracks(playlist) }
        catch { errorMessage = error.localizedDescription }
    }

    func play(_ track: Track) async {
        protectedTrack = nil
        isBusy = true
        defer { isBusy = false }
        do {
            let (url, preview) = try await service.audio(for: track)
            if let finishedObserver { NotificationCenter.default.removeObserver(finishedObserver) }
            player?.pause()
            let item = AVPlayerItem(url: url)
            player = AVPlayer(playerItem: item)
            finishedObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.isPlaying = false }
            }
            activeTrack = track
            isPreview = preview
            try AVAudioSession.sharedInstance().setActive(true)
            player?.play()
            isPlaying = true
            updateNowPlaying()
        } catch {
            if error.localizedDescription.contains("受保护音频") { protectedTrack = track }
            errorMessage = error.localizedDescription
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
        updateNowPlaying()
    }

    func resume() {
        player?.play()
        isPlaying = true
        updateNowPlaying()
    }

    func togglePlayback() { isPlaying ? pause() : resume() }

    func logout() {
        service.logout()
        account = nil
        playlists = []
        likedTracks = []
        recentTracks = []
        collectedPlaylists = []
    }

    private func updateNowPlaying() {
        guard let activeTrack else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: activeTrack.title,
            MPMediaItemPropertyArtist: activeTrack.artist,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
    }
}
