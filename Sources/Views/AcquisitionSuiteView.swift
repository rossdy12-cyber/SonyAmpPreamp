import SwiftUI

// MARK: - TAB 3: SOULSEEKR (SLSKD P2P FLAC/MP3 ACQUISITION)
struct SoulSeekrView: View {
    @ObservedObject var acq: AcquisitionClient
    let goldAccent: Color
    let panelBg: Color
    @State private var showConfig: Bool = false

    private var displayedResults: [SlskdSearchFile] {
        if acq.slskdOnlyFLAC {
            return acq.slskdResults.filter { $0.isLossless }
        }
        return acq.slskdResults
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    slskdHeaderCard
                    searchBarCard
                    if !acq.slskdTransfers.isEmpty {
                        activeTransfersCard
                    }
                    resultsCard
                }
                .padding(14)
            }
            .background(Color(red: 0.06, green: 0.06, blue: 0.08))
            .navigationTitle("SoulSeekr P2P (slskd)")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                Task { await acq.refreshSlskdTransfers() }
            }
        }
    }

    private var slskdHeaderCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "arrow.down.doc.fill")
                    .foregroundColor(goldAccent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("TrueNAS Soulseek P2P Daemon (slskd)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                    Text(acq.slskdStatus)
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                        .lineLimit(2)
                }
                Spacer()
                Button(showConfig ? "Hide" : "Setup") {
                    showConfig.toggle()
                }
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(goldAccent)
            }

            if showConfig {
                VStack(spacing: 8) {
                    TextField("slskd URL (http://100.85.127.42:5030)", text: $acq.slskdURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(size: 12, design: .monospaced))
                        .padding(8)
                        .background(Color.black.opacity(0.4))
                        .cornerRadius(6)
                    SecureField("X-API-Key", text: $acq.slskdApiKey)
                        .font(.system(size: 12, design: .monospaced))
                        .padding(8)
                        .background(Color.black.opacity(0.4))
                        .cornerRadius(6)
                }
            }
        }
        .padding(12)
        .background(panelBg)
        .cornerRadius(12)
    }

    private var searchBarCard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(goldAccent)
                TextField("Search P2P FLAC / 320kbps MP3 (Artist - Track/Album)...", text: $acq.slskdSearchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundColor(.white)
                    .onSubmit {
                        Task { await acq.searchSoulseek() }
                    }
                if !acq.slskdSearchText.isEmpty {
                    Button {
                        acq.slskdSearchText = ""
                        acq.slskdResults = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding(10)
            .background(Color.black.opacity(0.45))
            .cornerRadius(8)

            HStack {
                Toggle("Lossless FLAC/WAV Only", isOn: $acq.slskdOnlyFLAC)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .tint(goldAccent)

                Spacer()

                Button {
                    Task { await acq.searchSoulseek() }
                } label: {
                    HStack(spacing: 6) {
                        if acq.slskdIsSearching {
                            ProgressView().tint(.black)
                        } else {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                        }
                        Text(acq.slskdIsSearching ? "Searching..." : "Search P2P")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(goldAccent)
                    .cornerRadius(8)
                }
            }
        }
        .padding(12)
        .background(panelBg)
        .cornerRadius(12)
    }

    private var activeTransfersCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("ACTIVE TRUENAS SLSKD DOWNLOADS (\(acq.slskdTransfers.count))")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .foregroundColor(goldAccent)
                Spacer()
                Button("Refresh") {
                    Task { await acq.refreshSlskdTransfers() }
                }
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(goldAccent)
            }

            ForEach(acq.slskdTransfers.prefix(10)) { t in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(t.shortName)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Spacer()
                        Text("\(Int(t.percentComplete.rounded()))% • \(t.state)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(goldAccent)
                    }
                    ProgressView(value: min(100, max(0, t.percentComplete)), total: 100)
                        .tint(goldAccent)
                }
                .padding(8)
                .background(Color.black.opacity(0.35))
                .cornerRadius(8)
            }
        }
        .padding(12)
        .background(panelBg)
        .cornerRadius(12)
    }

    private var resultsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("P2P SEARCH RESULTS (\(displayedResults.count))")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundColor(goldAccent)

            if displayedResults.isEmpty {
                Text("Search any artist, album, or rare release above to query the Soulseek P2P network via TrueNAS slskd.")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(panelBg)
                    .cornerRadius(10)
            } else {
                ForEach(displayedResults) { file in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(file.shortName)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Text("\(file.folderName) • @\(file.username)")
                                .font(.system(size: 11))
                                .foregroundColor(.gray)
                                .lineLimit(1)
                            HStack(spacing: 6) {
                                Text(file.qualityBadge)
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(file.isLossless ? Color.green.opacity(0.25) : goldAccent.opacity(0.2))
                                    .foregroundColor(file.isLossless ? .green : goldAccent)
                                    .cornerRadius(4)
                                Text(file.sizeMB)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.gray)
                                if file.hasFreeUploadSlot {
                                    Text("Fast Slot")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.green)
                                }
                            }
                        }
                        Spacer()
                        Button {
                            Task { await acq.enqueueSlskdDownload(file: file) }
                        } label: {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 26))
                                .foregroundColor(goldAccent)
                        }
                    }
                    .padding(10)
                    .background(panelBg)
                    .cornerRadius(10)
                }
            }
        }
    }
}

// MARK: - TAB 4: ENCORE (LIDARR ARTIST DISCOVERY & REQUESTS)
struct EncoreLidarrView: View {
    @ObservedObject var acq: AcquisitionClient
    let goldAccent: Color
    let panelBg: Color
    @State private var showConfig: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    lidarrHeaderCard
                    artistLookupCard
                    if !acq.lidarrLookupResults.isEmpty {
                        lookupResultsSection
                    }
                    if !acq.lidarrQueue.isEmpty {
                        lidarrQueueSection
                    }
                    monitoredArtistsSection
                }
                .padding(14)
            }
            .background(Color(red: 0.06, green: 0.06, blue: 0.08))
            .navigationTitle("Encore (Lidarr)")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if acq.lidarrArtists.isEmpty {
                    Task { await acq.loadLidarrLibraryAndQueue() }
                }
            }
        }
    }

    private var lidarrHeaderCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "opticaldisc.fill")
                    .foregroundColor(goldAccent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("TrueNAS Lidarr Music Manager (:30071)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                    Text(acq.lidarrStatus)
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }
                Spacer()
                Button(showConfig ? "Hide" : "Setup") {
                    showConfig.toggle()
                }
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(goldAccent)
            }

            if showConfig {
                VStack(spacing: 8) {
                    TextField("Lidarr URL (http://100.85.127.42:30071)", text: $acq.lidarrURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(size: 12, design: .monospaced))
                        .padding(8)
                        .background(Color.black.opacity(0.4))
                        .cornerRadius(6)
                    SecureField("Lidarr API Key", text: $acq.lidarrApiKey)
                        .font(.system(size: 12, design: .monospaced))
                        .padding(8)
                        .background(Color.black.opacity(0.4))
                        .cornerRadius(6)
                }
            }
        }
        .padding(12)
        .background(panelBg)
        .cornerRadius(12)
    }

    private var artistLookupCard: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(goldAccent)
            TextField("Add new artist to Lidarr (MusicBrainz lookup)...", text: $acq.lidarrSearchTerm)
                .textInputAutocapitalization(.words)
                .foregroundColor(.white)
                .onSubmit {
                    Task { await acq.lookupLidarrArtists() }
                }
            Button {
                Task { await acq.lookupLidarrArtists() }
            } label: {
                Text("Lookup")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(goldAccent)
                    .cornerRadius(8)
            }
        }
        .padding(10)
        .background(panelBg)
        .cornerRadius(10)
    }

    private var lookupResultsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("ADD ARTIST TO TRUENAS LIDARR")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .foregroundColor(goldAccent)
                Spacer()
                Button("Close") { acq.lidarrLookupResults = [] }
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
            }

            ForEach(acq.lidarrLookupResults) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.artistName)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                        if !item.overview.isEmpty {
                            Text(item.overview)
                                .font(.system(size: 11))
                                .foregroundColor(.gray)
                                .lineLimit(2)
                        }
                    }
                    Spacer()
                    Button {
                        Task { await acq.addArtistToLidarr(item) }
                    } label: {
                        Label("Add & Search", systemImage: "plus.circle.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(goldAccent)
                            .cornerRadius(8)
                    }
                }
                .padding(10)
                .background(panelBg)
                .cornerRadius(10)
            }
        }
    }

    private var lidarrQueueSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LIDARR DOWNLOAD QUEUE (\(acq.lidarrQueue.count))")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundColor(goldAccent)

            ForEach(acq.lidarrQueue) { q in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(q.title)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text("\(q.artistName) • \(q.protocolName.uppercased()) • \(q.status)")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                    }
                    Spacer()
                    Text("\(q.progressPercent)%")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(goldAccent)
                }
                .padding(10)
                .background(panelBg)
                .cornerRadius(8)
            }
        }
    }

    private var monitoredArtistsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("MONITORED LIDARR ARTISTS (\(acq.lidarrArtists.count))")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .foregroundColor(goldAccent)
                Spacer()
                Button("Refresh") {
                    Task { await acq.loadLidarrLibraryAndQueue() }
                }
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(goldAccent)
            }

            ForEach(acq.lidarrArtists) { artist in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(artist.artistName)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                        Text("\(artist.albumCount) albums • \(artist.trackCount) tracks • \(String(format: "%.1f GB", Double(artist.sizeOnDisk) / 1_073_741_824.0))")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.gray)
                    }
                    Spacer()
                    Button {
                        Task { await acq.triggerLidarrArtistSearch(artistId: artist.id, artistName: artist.artistName) }
                    } label: {
                        Label("Search Missing", systemImage: "magnifyingglass.circle.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(goldAccent)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(6)
                    }
                }
                .padding(10)
                .background(panelBg)
                .cornerRadius(10)
            }
        }
    }
}
