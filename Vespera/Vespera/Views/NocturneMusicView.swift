import SwiftUI

struct NocturneMusicView: View {
    @EnvironmentObject var engine: CPDS10Engine
    @State private var searchText = ""
    @State private var searchResults: [NavSong] = []
    @State private var selectedAlbum: NavAlbum?
    @State private var albumSongs: [NavSong] = []
    @State private var loadingAlbum = false

    private let albumColumns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        NavigationStack {
            ZStack {
                CathedralBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        // Now Playing Deck + Simultaneous Sleep Layer Toggle
                        nowPlayingDeck

                        // Quick Nightfall Shuffle Button
                        Button {
                            Task { await engine.playNightfallShuffle() }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "shuffle.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(VesperaTheme.ember)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Summon Nightfall 40W Shuffle")
                                        .font(VesperaTheme.gothic(15, weight: .bold))
                                        .foregroundStyle(VesperaTheme.bone)
                                    Text("Streams 35 random tracks from your TrueNAS Navidrome library")
                                        .font(VesperaTheme.engraved(11))
                                        .foregroundStyle(VesperaTheme.ash)
                                }
                                Spacer()
                                Image(systemName: "play.fill")
                                    .foregroundStyle(VesperaTheme.blood)
                            }
                            .gothicCard(highlighted: true)
                        }
                        .buttonStyle(.plain)

                        // Search Results (if searching)
                        if !searchResults.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("SEARCH RESULTS (\(searchResults.count))")
                                    .font(VesperaTheme.engraved(11, weight: .bold))
                                    .tracking(1.6)
                                    .foregroundStyle(VesperaTheme.ash)

                                ForEach(Array(searchResults.enumerated()), id: \.element.id) { idx, song in
                                    songRow(song, in: searchResults, index: idx)
                                }
                            }
                        }

                        // Playlists Horizontal Bar
                        if !engine.navPlaylists.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("NAVIDROME PLAYLISTS")
                                    .font(VesperaTheme.engraved(11, weight: .bold))
                                    .tracking(1.6)
                                    .foregroundStyle(VesperaTheme.ash)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(engine.navPlaylists) { pl in
                                            Button {
                                                Task { await engine.playPlaylist(pl) }
                                            } label: {
                                                HStack(spacing: 8) {
                                                    Image(systemName: "music.note.list")
                                                        .foregroundStyle(VesperaTheme.ember)
                                                    VStack(alignment: .leading, spacing: 2) {
                                                        Text(pl.name)
                                                            .font(VesperaTheme.gothic(14, weight: .semibold))
                                                            .foregroundStyle(VesperaTheme.bone)
                                                        Text("\(pl.songCount) tracks")
                                                            .font(VesperaTheme.mono(10))
                                                            .foregroundStyle(VesperaTheme.ash)
                                                    }
                                                }
                                                .padding(.horizontal, 14)
                                                .padding(.vertical, 10)
                                                .background(RoundedRectangle(cornerRadius: 12).fill(VesperaTheme.surface))
                                                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(VesperaTheme.blood.opacity(0.5), lineWidth: 1))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                        }

                        // Albums Grid
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("TRUENAS NAVIDROME ALBUMS (\(engine.navAlbums.count))")
                                    .font(VesperaTheme.engraved(11, weight: .bold))
                                    .tracking(1.6)
                                    .foregroundStyle(VesperaTheme.ash)
                                Spacer()
                                Button {
                                    Task { await engine.loadNavidromeLibrary() }
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 13))
                                        .foregroundStyle(VesperaTheme.blood)
                                }
                            }

                            if engine.isLoadingLibrary && engine.navAlbums.isEmpty {
                                HStack {
                                    Spacer()
                                    ProgressView().tint(VesperaTheme.blood)
                                    Spacer()
                                }
                                .padding(30)
                            } else if let err = engine.libraryError, engine.navAlbums.isEmpty {
                                VStack(spacing: 10) {
                                    Text(err)
                                        .font(VesperaTheme.engraved(13))
                                        .foregroundStyle(VesperaTheme.ash)
                                        .multilineTextAlignment(.center)
                                    Button("Retry Connection") {
                                        Task { await engine.loadNavidromeLibrary() }
                                    }
                                    .font(VesperaTheme.mono(12, weight: .bold))
                                    .foregroundStyle(VesperaTheme.ember)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(20)
                            } else {
                                LazyVGrid(columns: albumColumns, spacing: 14) {
                                    ForEach(engine.navAlbums) { album in
                                        albumCard(album)
                                            .onTapGesture {
                                                selectedAlbum = album
                                                Task { await loadAlbumDetail(album) }
                                            }
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Nocturne Music")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search TrueNAS songs, artists, OSTs…")
            .onSubmit(of: .search) {
                Task {
                    if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                        searchResults = []
                    } else {
                        searchResults = (try? await engine.subsonicClient.searchSongs(query: searchText)) ?? []
                    }
                }
            }
            .onChange(of: searchText) { _, newVal in
                if newVal.isEmpty { searchResults = [] }
            }
            .sheet(item: $selectedAlbum) { album in
                albumDetailSheet(album)
            }
        }
    }

    private var nowPlayingDeck: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(VesperaTheme.raised)
                        .frame(width: 64, height: 64)
                    if let song = engine.currentSong, let url = engine.coverURL(for: song.coverArt) {
                        AsyncImage(url: url) { img in
                            img.resizable().scaledToFill()
                        } placeholder: {
                            Image(systemName: "music.note").foregroundStyle(VesperaTheme.blood)
                        }
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    } else {
                        Image(systemName: "hifispeaker.2.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(VesperaTheme.blood)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(engine.currentSong?.title ?? "Ready to Stream to CP-DS10")
                        .font(VesperaTheme.gothic(17, weight: .bold))
                        .foregroundStyle(VesperaTheme.bone)
                        .lineLimit(1)
                    Text(engine.currentSong?.artist ?? "Select any album or Nightfall Shuffle below")
                        .font(VesperaTheme.engraved(13))
                        .foregroundStyle(VesperaTheme.ash)
                        .lineLimit(1)
                    Text(engine.activeNavBase)
                        .font(VesperaTheme.mono(10))
                        .foregroundStyle(VesperaTheme.blood)
                        .lineLimit(1)
                }
                Spacer()
            }

            if engine.currentSong != nil {
                VStack(spacing: 4) {
                    Slider(
                        value: Binding(
                            get: { min(engine.currentTime, max(1, engine.duration)) },
                            set: { engine.seekMusic(to: $0) }
                        ),
                        in: 0...max(1, engine.duration)
                    )
                    .tint(VesperaTheme.blood)

                    HStack {
                        Text(formatSeconds(Int(engine.currentTime)))
                            .font(VesperaTheme.mono(10))
                            .foregroundStyle(VesperaTheme.ash)
                        Spacer()
                        Text(formatSeconds(Int(engine.duration)))
                            .font(VesperaTheme.mono(10))
                            .foregroundStyle(VesperaTheme.ash)
                    }
                }
            }

            HStack(spacing: 24) {
                Button { engine.previousTrack() } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(VesperaTheme.bone)
                }
                Button { engine.toggleMusicPlayback() } label: {
                    Image(systemName: engine.isMusicPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(VesperaTheme.ember)
                }
                Button { engine.nextTrack() } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(VesperaTheme.bone)
                }
                Spacer()
                // Layer Sleep Soundscape Under Music Toggle
                Button {
                    engine.toggleSoundscape()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "cloud.rain.fill")
                        Text(engine.isSoundscapePlaying ? "Rain Mix ON" : "+ Sleep Layer")
                            .font(VesperaTheme.mono(11, weight: .bold))
                    }
                    .foregroundStyle(engine.isSoundscapePlaying ? Color.black : VesperaTheme.bone)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(engine.isSoundscapePlaying ? VesperaTheme.ember : VesperaTheme.raised))
                }
            }
        }
        .gothicCard(highlighted: engine.isMusicPlaying)
    }

    private func albumCard(_ album: NavAlbum) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(VesperaTheme.raised)
                    .aspectRatio(1, contentMode: .fit)
                if let url = engine.coverURL(for: album.coverArt) {
                    AsyncImage(url: url) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        ProgressView().tint(VesperaTheme.blood)
                    }
                    .aspectRatio(1, contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    Image(systemName: "opticaldisc.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(VesperaTheme.blood)
                }
            }

            Text(album.name)
                .font(VesperaTheme.gothic(14, weight: .semibold))
                .foregroundStyle(VesperaTheme.bone)
                .lineLimit(1)

            Text("\(album.artist) • \(album.songCount) tracks")
                .font(VesperaTheme.engraved(11))
                .foregroundStyle(VesperaTheme.ash)
                .lineLimit(1)
        }
        .gothicCard()
    }

    private func songRow(_ song: NavSong, in queue: [NavSong], index: Int) -> some View {
        let isCurrent = engine.currentSong?.id == song.id
        return Button {
            engine.playQueue(queue, startIndex: index)
        } label: {
            HStack(spacing: 12) {
                Text("\(index + 1)")
                    .font(VesperaTheme.mono(12))
                    .foregroundStyle(isCurrent ? VesperaTheme.ember : VesperaTheme.ash)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(VesperaTheme.gothic(15, weight: isCurrent ? .bold : .medium))
                        .foregroundStyle(isCurrent ? VesperaTheme.ember : VesperaTheme.bone)
                        .lineLimit(1)
                    Text(song.artist)
                        .font(VesperaTheme.engraved(12))
                        .foregroundStyle(VesperaTheme.ash)
                        .lineLimit(1)
                }
                Spacer()
                Text(formatSeconds(song.duration))
                    .font(VesperaTheme.mono(11))
                    .foregroundStyle(VesperaTheme.ash)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: 10).fill(isCurrent ? VesperaTheme.crimson.opacity(0.25) : VesperaTheme.surface))
        }
        .buttonStyle(.plain)
    }

    private func albumDetailSheet(_ album: NavAlbum) -> some View {
        NavigationStack {
            ZStack {
                CathedralBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 14) {
                            if let url = engine.coverURL(for: album.coverArt) {
                                AsyncImage(url: url) { img in
                                    img.resizable().scaledToFill()
                                } placeholder: {
                                    Color.black
                                }
                                .frame(width: 84, height: 84)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(album.name)
                                    .font(VesperaTheme.gothic(20, weight: .bold))
                                    .foregroundStyle(VesperaTheme.bone)
                                Text(album.artist)
                                    .font(VesperaTheme.engraved(14))
                                    .foregroundStyle(VesperaTheme.ash)
                                Button {
                                    if !albumSongs.isEmpty {
                                        engine.playQueue(albumSongs, startIndex: 0)
                                        selectedAlbum = nil
                                    }
                                } label: {
                                    Label("Play Full Album on CP-DS10", systemImage: "play.fill")
                                        .font(VesperaTheme.mono(12, weight: .bold))
                                        .foregroundStyle(Color.black)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .background(Capsule().fill(VesperaTheme.ember))
                                }
                                .padding(.top, 4)
                            }
                        }
                        .padding(.bottom, 6)

                        if loadingAlbum {
                            ProgressView().tint(VesperaTheme.blood).frame(maxWidth: .infinity).padding(30)
                        } else {
                            ForEach(Array(albumSongs.enumerated()), id: \.element.id) { idx, song in
                                songRow(song, in: albumSongs, index: idx)
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle(album.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { selectedAlbum = nil }
                        .foregroundStyle(VesperaTheme.ember)
                }
            }
        }
    }

    private func loadAlbumDetail(_ album: NavAlbum) async {
        loadingAlbum = true
        albumSongs = (try? await engine.subsonicClient.fetchAlbumSongs(albumID: album.id)) ?? []
        loadingAlbum = false
    }

    private func formatSeconds(_ total: Int) -> String {
        let m = max(0, total) / 60
        let s = max(0, total) % 60
        return String(format: "%d:%02d", m, s)
    }
}
