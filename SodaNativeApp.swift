import SwiftUI

@main
struct SodaNativeApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .tint(SodaStyle.accent)
        }
    }
}

private enum SodaStyle {
    static let accent = Color(red: 0.91, green: 0.28, blue: 0.30)
    static let background = Color(red: 0.91, green: 0.91, blue: 0.93)
    static let card = Color.white.opacity(0.54)
}

private struct RootView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        TabView {
            Tab("推荐", systemImage: "house.fill") {
                NavigationStack { DiscoveryView(title: "推荐", query: "热门音乐") }
            }
            Tab("精选", systemImage: "square.grid.2x2.fill") {
                NavigationStack { DiscoveryView(title: "精选", query: "华语音乐") }
            }
            Tab("漫游", systemImage: "dot.radiowaves.left.and.right") {
                NavigationStack { DiscoveryView(title: "漫游", query: "新歌") }
            }
            Tab("我的", systemImage: "person.crop.circle.fill") {
                NavigationStack { LibraryView() }
            }
            Tab(role: .search) {
                NavigationStack { SearchView() }
            }
        }
        .tabViewBottomAccessory(isEnabled: state.activeTrack != nil) {
            MiniPlayer()
        }
        .sheet(isPresented: $state.showingPlayer) {
            FullPlayer()
        }
        .sheet(isPresented: $state.showingLogin) {
            LoginView()
        }
        .alert("提示", isPresented: Binding(
            get: { state.errorMessage != nil },
            set: { if !$0 { state.errorMessage = nil } }
        )) {
            if state.requiresLogin {
                Button("重新扫码登录") {
                    state.errorMessage = nil
                    state.requiresLogin = false
                    state.showingLogin = true
                }
            }
            if let track = state.protectedTrack,
               let url = URL(string: "https://www.qishui.com/track/\(track.id)") {
                Button("在官方汽水音乐中打开") {
                    UIApplication.shared.open(url)
                    state.protectedTrack = nil
                }
            }
            Button("知道了", role: .cancel) {
                state.errorMessage = nil
                state.protectedTrack = nil
            }
        } message: {
            Text(state.errorMessage ?? "")
        }
    }
}

private struct DiscoveryView: View {
    @EnvironmentObject private var state: AppState
    let title: String
    let query: String
    @State private var tracks: [Track] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title)
                            .font(.system(size: 43, weight: .bold, design: .rounded))
                        Text("听见此刻的好音乐")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 42))
                        .foregroundStyle(SodaStyle.accent)
                }
                .padding(.top, 32)

                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: "sparkles.rectangle.stack")
                        .font(.system(size: 34))
                        .foregroundStyle(SodaStyle.accent)
                    Text("开始探索")
                        .font(.title2.bold())
                    Text("从汽水音乐中寻找你喜欢的旋律")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
                .background(SodaStyle.card, in: RoundedRectangle(cornerRadius: 32))

                HStack {
                    Text("热门发现")
                        .font(.title2.bold())
                    Spacer()
                    if state.isBusy { ProgressView() }
                }
                VStack(spacing: 0) {
                    ForEach(tracks) { track in
                        TrackRow(track: track)
                        if track.id != tracks.last?.id { Divider().padding(.leading, 72) }
                    }
                }
                .background(SodaStyle.card, in: RoundedRectangle(cornerRadius: 30))
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 30)
        }
        .background(SodaStyle.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task(id: query) {
            do { tracks = try await QishuiService.shared.search(query) }
            catch { state.report(error) }
        }
        .refreshable {
            do { tracks = try await QishuiService.shared.search(query) }
            catch { state.report(error) }
        }
    }
}

private struct SearchView: View {
    @EnvironmentObject private var state: AppState
    @State private var query = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("搜索")
                    .font(.system(size: 43, weight: .bold, design: .rounded))
                    .padding(.top, 30)
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("歌曲或艺人", text: $query)
                        .submitLabel(.search)
                        .onSubmit { Task { await state.search(query) } }
                    if !query.isEmpty {
                        Button("搜索") { Task { await state.search(query) } }
                            .fontWeight(.semibold)
                    }
                }
                .padding(18)
                .background(SodaStyle.card, in: RoundedRectangle(cornerRadius: 22))

                if state.isBusy { ProgressView().frame(maxWidth: .infinity).padding() }
                VStack(spacing: 0) {
                    ForEach(state.searchResults) { track in
                        TrackRow(track: track)
                        if track.id != state.searchResults.last?.id { Divider().padding(.leading, 72) }
                    }
                }
                .background(SodaStyle.card, in: RoundedRectangle(cornerRadius: 30))
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 30)
        }
        .background(SodaStyle.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct LibraryView: View {
    @EnvironmentObject private var state: AppState
    @State private var showingLogin = false
    @State private var showingLikes = false
    @State private var showingRecent = false
    @State private var showingCollected = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                HStack {
                    Spacer()
                    Button { showingLogin = true } label: {
                        Image(systemName: "gearshape")
                            .font(.title2)
                            .frame(width: 48, height: 48)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("账号设置")
                }
                .padding(.top, 18)

                Text("我的")
                    .font(.system(size: 43, weight: .bold, design: .rounded))

                Button {
                    if state.account == nil { showingLogin = true }
                } label: {
                    HStack(spacing: 18) {
                        if let image = state.account?.avatarURL.flatMap(URL.init(string:)) {
                            AsyncImage(url: image) { picture in picture.resizable().scaledToFill() }
                                placeholder: { Circle().fill(SodaStyle.accent.opacity(0.15)) }
                                .frame(width: 62, height: 62).clipShape(Circle())
                        } else {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 60))
                                .foregroundStyle(SodaStyle.accent)
                        }
                        Text(state.account?.nickname ?? "用抖音扫码登录")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        if state.account?.isVIP == true {
                            Text("VIP")
                                .font(.caption.bold())
                                .foregroundStyle(SodaStyle.accent)
                                .padding(.horizontal, 5)
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(SodaStyle.accent))
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, minHeight: 108)
                    .background(SodaStyle.card, in: RoundedRectangle(cornerRadius: 30))
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 12) {
                    Text("我的音乐")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 18)
                    VStack(spacing: 0) {
                        Button { showingLikes = true } label: {
                            LibraryRow(symbol: "heart.fill", title: "我喜欢的音乐", highlighted: true)
                        }
                        Divider().padding(.leading, 72)
                        LibraryRow(symbol: "calendar", title: "每日推荐 · 开发中", available: false)
                        Divider().padding(.leading, 72)
                        Button { showingRecent = true } label: {
                            LibraryRow(symbol: "clock.fill", title: "最近播放")
                        }
                        Divider().padding(.leading, 72)
                        Button { showingCollected = true } label: {
                            LibraryRow(symbol: "star.fill", title: "我的收藏")
                        }
                    }
                    .background(SodaStyle.card, in: RoundedRectangle(cornerRadius: 30))
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("创建的歌单")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 18)
                    VStack(spacing: 0) {
                        ForEach(state.playlists) { playlist in
                            NavigationLink {
                                PlaylistView(playlist: playlist)
                            } label: {
                                LibraryRow(symbol: "music.note.list", title: playlist.title)
                            }
                            if playlist.id != state.playlists.last?.id { Divider().padding(.leading, 72) }
                        }
                        if state.playlists.isEmpty {
                            Text(state.account == nil ? "登录后查看你的歌单" : "暂无歌单")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(30)
                        }
                    }
                    .background(SodaStyle.card, in: RoundedRectangle(cornerRadius: 30))
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 30)
        }
        .background(SodaStyle.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task(id: state.account?.userId) { await state.loadLibrary() }
        .refreshable { await state.loadLibrary() }
        .sheet(isPresented: $showingLogin) { LoginView() }
        .sheet(isPresented: $showingLikes) {
            NavigationStack { TrackCollectionView(title: "我喜欢的音乐", tracks: state.likedTracks) }
        }
        .sheet(isPresented: $showingRecent) {
            NavigationStack { TrackCollectionView(title: "最近播放", tracks: state.recentTracks) }
        }
        .sheet(isPresented: $showingCollected) {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(state.collectedPlaylists) { playlist in
                            NavigationLink {
                                PlaylistView(playlist: playlist)
                            } label: {
                                LibraryRow(symbol: "music.note.list", title: playlist.title)
                            }
                        }
                    }
                    .background(SodaStyle.card, in: RoundedRectangle(cornerRadius: 30))
                    .padding(20)
                }
                .background(SodaStyle.background.ignoresSafeArea())
                .navigationTitle("我的收藏")
            }
        }
    }
}

private struct LibraryRow: View {
    let symbol: String
    let title: String
    var highlighted = false
    var available = true

    var body: some View {
        HStack(spacing: 20) {
            Image(systemName: symbol)
                .font(.system(size: 25))
                .foregroundStyle(SodaStyle.accent)
                .frame(width: 30)
            Text(title)
                .font(.system(size: 18))
                .foregroundStyle(!available ? Color.secondary : highlighted ? SodaStyle.accent : Color.primary)
            Spacer()
            if available {
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 24)
        .frame(height: 63)
        .contentShape(Rectangle())
    }
}

private struct TrackRow: View {
    @EnvironmentObject private var state: AppState
    let track: Track

    var body: some View {
        Button {
            Task { await state.play(track) }
        } label: {
            HStack(spacing: 14) {
                Artwork(url: track.artwork, size: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.title).font(.body.weight(.medium)).lineLimit(1)
                    Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Image(systemName: "play.fill")
                    .foregroundStyle(SodaStyle.accent)
            }
            .padding(.horizontal, 16)
            .frame(height: 72)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct Artwork: View {
    let url: URL?
    let size: CGFloat

    var body: some View {
        AsyncImage(url: url) { image in image.resizable().scaledToFill() }
            placeholder: { Color.gray.opacity(0.18).overlay(Image(systemName: "music.note")) }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.19))
    }
}

private struct PlaylistView: View {
    @EnvironmentObject private var state: AppState
    let playlist: Playlist

    var body: some View {
        TrackCollectionView(title: playlist.title, tracks: state.selectedPlaylistTracks)
            .task(id: playlist.id) { await state.loadPlaylist(playlist) }
    }
}

private struct TrackCollectionView: View {
    let title: String
    let tracks: [Track]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(tracks) { track in
                    TrackRow(track: track)
                    if track.id != tracks.last?.id { Divider().padding(.leading, 72) }
                }
            }
            .background(SodaStyle.card, in: RoundedRectangle(cornerRadius: 30))
            .padding(20)
        }
        .background(SodaStyle.background.ignoresSafeArea())
        .navigationTitle(title)
    }
}

private struct MiniPlayer: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        if let track = state.activeTrack {
            HStack(spacing: 12) {
                Button { state.showingPlayer = true } label: {
                    HStack(spacing: 12) {
                        Artwork(url: track.artwork, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title).font(.subheadline.bold()).lineLimit(1)
                            Text(state.isPreview ? "试听 · \(track.artist)" : track.artist)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                Button { state.togglePlayback() } label: {
                    Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(state.isPlaying ? "暂停" : "播放")
            }
            .padding(.horizontal, 12)
            .frame(height: 56)
        }
    }
}

private struct FullPlayer: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let track = state.activeTrack {
            VStack(spacing: 26) {
                HStack {
                    Button { dismiss() } label: { Image(systemName: "chevron.down") }
                    Spacer()
                    Text("正在播放").font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "ellipsis").opacity(0)
                }
                .padding(.top, 18)
                Spacer()
                Artwork(url: track.artwork, size: 290)
                    .shadow(color: .black.opacity(0.14), radius: 26, y: 20)
                VStack(alignment: .leading, spacing: 7) {
                    Text(track.title).font(.title.bold())
                    Text(track.artist).font(.title3).foregroundStyle(.secondary)
                    if state.isPreview {
                        Label("当前曲目仅提供试听片段", systemImage: "info.circle")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
                Button { state.togglePlayback() } label: {
                    Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 38))
                        .frame(width: 90, height: 90)
                }
                .buttonStyle(.glassProminent)
                Spacer()
            }
            .padding(.horizontal, 30)
            .background(SodaStyle.background.ignoresSafeArea())
        }
    }
}

private struct LoginView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var code: LoginCode?
    @State private var message = "正在生成二维码…"
    @State private var polling: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let account = state.account {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 65)).foregroundStyle(SodaStyle.accent)
                    Text(account.nickname).font(.title2.bold())
                    Button("退出登录", role: .destructive) {
                        state.logout()
                        dismiss()
                    }
                } else {
                    Text("用抖音扫码登录")
                        .font(.title2.bold())
                    if let code {
                        Image(uiImage: code.image)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 240, height: 240)
                            .padding(18)
                            .background(.white, in: RoundedRectangle(cornerRadius: 20))
                    } else { ProgressView().frame(height: 260) }
                    Text(message)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Text("可截图保存二维码，再从抖音扫码页面的相册中识别。请在抖音内确认授权。")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Button("刷新二维码") { beginLogin() }
                }
                Spacer()
            }
            .padding(30)
            .frame(maxWidth: .infinity)
            .background(SodaStyle.background.ignoresSafeArea())
            .navigationTitle("账号")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }
        .onAppear { if state.account == nil { beginLogin() } }
        .onDisappear { polling?.cancel() }
    }

    private func beginLogin() {
        polling?.cancel()
        code = nil
        message = "正在生成二维码…"
        polling = Task {
            do {
                let value = try await QishuiService.shared.startLogin()
                code = value
                message = "等待抖音扫码"
                while !Task.isCancelled {
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                    switch try await QishuiService.shared.checkLogin(value) {
                    case .waiting: message = "等待抖音扫码"
                    case .scanned: message = "已扫码，请在抖音中确认"
                    case .confirmed(let account):
                        state.account = account
                        state.requiresLogin = false
                        dismiss()
                        return
                    case .expired: message = "二维码已过期，请刷新"; return
                    case .refused: message = "授权已取消，请刷新二维码"; return
                    }
                }
            } catch is CancellationError {
            } catch {
                if !Task.isCancelled && !RequestPolicy.isCancellation(error) {
                    message = error.localizedDescription
                }
            }
        }
    }
}
