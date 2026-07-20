import SwiftUI

struct AudioMetadataView: View {
    let projectName: String
    let suggestedTitle: String
    let bpm: Double?
    let lyrics: String
    let audioURL: URL?
    @StateObject private var model = AudioMetadataViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                HStack(alignment: .top, spacing: 18) {
                    formCard
                    artworkCard
                }
                if let info = model.technicalInfo { technicalCard(info) }
                if ["wav", "wave"].contains(model.sourceURL?.pathExtension.lowercased() ?? "") { mp3Card }
                actionCard
            }
            .frame(maxWidth: 920)
            .padding(30)
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            model.synchronize(projectName: projectName, suggestedTitle: suggestedTitle, bpm: bpm)
            if let audioURL { model.loadAudio(audioURL) }
        }
        .onChange(of: projectName) { _, value in
            model.synchronize(projectName: value, suggestedTitle: suggestedTitle, bpm: bpm)
        }
        .onChange(of: suggestedTitle) { _, value in
            model.synchronize(projectName: projectName, suggestedTitle: value, bpm: bpm)
        }
        .onChange(of: audioURL) { _, value in if let value { model.loadAudio(value) } }
        .overlay { ProcessingOverlay(state: model.operationState, cancel: model.cancelProcessing) }
        .alert("Métadonnées audio", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(model.errorMessage ?? "") }
    }

    private var header: some View {
        HStack(spacing: 16) {
            AccentIcon(systemName: "waveform.badge.plus", color: AppTheme.cyan, size: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text("Métadonnées audio").font(.system(size: 30, weight: .bold, design: .rounded))
                Text("Taguer un export Suno sans réencoder ni modifier le son.").foregroundStyle(.secondary)
            }
            Spacer()
            CapsuleStatus(text: "Original protégé", systemName: "shield.checkered", color: AppTheme.green)
        }
    }

    private var formCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            Label("Informations", systemImage: "tag.fill").font(.headline)
            metadataField("TITRE", text: $model.title)
            metadataField("ARTISTE", text: $model.artist)
            HStack(spacing: 10) {
                metadataField("N° PISTE", text: $model.trackNumber).frame(width: 90)
                metadataField("FORMAT DU NOM", text: $model.filenameTemplate)
            }
            Text("Tokens : {track} {group} {title} {album} {year} {bpm}")
                .font(.caption2).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                metadataField("ALBUM / PROJET", text: $model.album)
                VStack(alignment: .leading, spacing: 6) {
                    Text("ANNÉE").font(.caption2.bold()).foregroundStyle(.secondary)
                    TextField("Année", value: $model.year, format: .number.grouping(.never))
                        .textFieldStyle(.plain).padding(11).fieldSurface()
                }.frame(width: 105)
            }
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("STYLE / GENRE").font(.caption2.bold()).foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        TextField("Style personnalisé", text: $model.genre)
                            .textFieldStyle(.plain)
                        Menu {
                            ForEach(Self.musicGenres, id: \.self) { genre in
                                Button(genre) { model.genre = genre }
                            }
                        } label: {
                            Image(systemName: "chevron.up.chevron.down")
                                .foregroundStyle(.secondary)
                                .padding(7)
                        }
                        .menuStyle(.borderlessButton)
                    }
                    .padding(.leading, 11)
                    .fieldSurface()
                }
                metadataField("BPM", text: $model.bpmText).frame(width: 110)
            }
            Toggle("Inclure les paroles dans le fichier", isOn: $model.includesLyrics)
                .toggleStyle(.switch)
            Text("La tonalité n’est jamais écrite. Les paroles sont désactivées par défaut.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .appPanel(radius: 20, padding: 20)
    }

    private var artworkCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            Label("Pochette", systemImage: "photo.fill").font(.headline)
            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.05))
                if let image = model.artworkImage {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    VStack(spacing: 9) {
                        Image(systemName: "photo.badge.plus").font(.system(size: 34)).foregroundStyle(.secondary)
                        Text("PNG ou JPEG").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 230, height: 230)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.10)) }
            Button("Choisir une pochette", systemImage: "photo.on.rectangle") { model.selectArtwork() }
                .buttonStyle(.bordered).frame(maxWidth: .infinity)
            if model.artworkImage != nil {
                Button(role: .destructive) { model.removeArtwork() } label: {
                    Label("Retirer la pochette", systemImage: "trash")
                }
                    .buttonStyle(.bordered).frame(maxWidth: .infinity)
            }
        }
        .appPanel(radius: 20, padding: 20)
    }

    private var actionCard: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.sourceURL?.lastPathComponent ?? "Aucun export sélectionné").font(.headline).lineLimit(1)
                Text(model.message ?? "Sortie : \(model.outputFilename) — le fichier original reste intact.")
                    .font(.caption).foregroundStyle(model.message == nil ? Color.secondary : AppTheme.green)
            }
            Spacer()
            Button("Choisir MP3/WAV", systemImage: "waveform") { model.selectAudio() }.buttonStyle(.bordered)
            Button("Écrire les métadonnées", systemImage: "tag.fill") { model.write(lyrics: lyrics) }
                .buttonStyle(.borderedProminent).disabled(model.sourceURL == nil || model.isWriting)
            if model.isWriting { ProgressView().controlSize(.small) }
        }
        .appPanel(radius: 18, padding: 18)
    }

    private var mp3Card: some View {
        VStack(alignment: .leading, spacing: 15) {
            Label("Conversion MP3", systemImage: "arrow.triangle.2.circlepath").font(.headline)
            HStack(spacing: 12) {
                settingPicker("MODE", selection: $model.encodingMode, values: MP3EncodingMode.allCases) { $0.rawValue }
                if model.encodingMode == .cbr {
                    settingPicker("DÉBIT", selection: $model.mp3Bitrate, values: MP3Bitrate.allCases) { $0.label }
                } else {
                    settingPicker("QUALITÉ", selection: $model.vbrQuality, values: MP3VBRQuality.allCases) { $0.label }
                }
                settingPicker("FRÉQUENCE", selection: $model.mp3SampleRate, values: MP3SampleRate.allCases) { $0.rawValue }
            }
            HStack {
                Text("LAME · joint stereo · qualité d’encodage maximale").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Convertir en MP3", systemImage: "waveform.badge.plus") { model.convertToMP3(lyrics: lyrics) }
                    .buttonStyle(.borderedProminent).disabled(model.isWriting)
            }
        }.appPanel(radius: 20, padding: 20)
    }

    private func settingPicker<Value: Hashable, Values: RandomAccessCollection>(
        _ label: String, selection: Binding<Value>, values: Values, title: @escaping (Value) -> String
    ) -> some View where Values.Element == Value {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption2.bold()).foregroundStyle(.secondary)
            Picker(label, selection: selection) { ForEach(Array(values), id: \.self) { Text(title($0)).tag($0) } }
                .labelsHidden().frame(maxWidth: .infinity)
        }.frame(maxWidth: .infinity)
    }

    private func technicalCard(_ info: AudioTechnicalInfo) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Informations techniques", systemImage: "waveform.path.ecg").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 10)], spacing: 10) {
                technicalValue("FORMAT", info.format)
                technicalValue("CODEC", info.codec)
                technicalValue("FRÉQUENCE", info.sampleRate.map { (Self.sampleRateFormatter.string(from: NSNumber(value: $0)) ?? String($0)) + " Hz" } ?? "—")
                technicalValue("PROFONDEUR", info.bitDepth.map { "\($0) bits" } ?? "Non applicable")
                technicalValue("DÉBIT", info.bitrateKbps.map { "\($0) kb/s" } ?? "—")
                technicalValue("CANAUX", info.channels == 1 ? "Mono" : (info.channels == 2 ? "Stéréo" : info.channels.map { String($0) } ?? "—"))
                technicalValue("DURÉE", info.duration.map(Self.durationString) ?? "—")
                technicalValue("TAILLE", ByteCountFormatter.string(fromByteCount: info.fileSize, countStyle: .file))
            }
        }.appPanel(radius: 20, padding: 20)
    }

    private func technicalValue(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 9, weight: .bold)).tracking(0.5).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold)).lineLimit(2)
        }.frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
            .padding(10).background(Color.primary.opacity(0.045))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private static let sampleRateFormatter: NumberFormatter = {
        let formatter = NumberFormatter(); formatter.numberStyle = .decimal; formatter.groupingSeparator = " "; return formatter
    }()

    private static func durationString(_ value: TimeInterval) -> String {
        let seconds = max(0, Int(value.rounded()))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private static let musicGenres = [
        "Alternative", "Alternative Rock", "Ambient", "Americana", "Art Pop", "Art Rock",
        "Blues", "Blues Rock", "Bossa Nova", "Chanson française", "Chillout", "Classical",
        "Country", "Dance", "Darkwave", "Disco", "Dream Pop", "Drum & Bass", "Dub", "Dubstep",
        "EDM", "Electro", "Electronic", "Emo", "Experimental", "Folk", "Folk Rock", "Funk",
        "Garage Rock", "Gospel", "Grunge", "Hard Rock", "Heavy Metal", "Hip-Hop", "House",
        "Indie", "Indie Folk", "Indie Pop", "Indie Rock", "Industrial", "Jazz", "Jazz Fusion",
        "Latin", "Lo-fi", "Metal", "Neo Soul", "New Wave", "Noise Rock", "Pop", "Pop Rock",
        "Post-Punk", "Post-Rock", "Progressive Rock", "Psychedelic", "Punk", "R&B", "Rap",
        "Reggae", "Rock", "Rockabilly", "Shoegaze", "Singer-Songwriter", "Soul", "Synthpop",
        "Synthwave", "Techno", "Trance", "Trip-Hop", "World"
    ]

    private func metadataField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption2.bold()).foregroundStyle(.secondary)
            TextField(label.capitalized, text: text).textFieldStyle(.plain).padding(11).fieldSurface()
        }.frame(maxWidth: .infinity)
    }
}

private extension View {
    func fieldSurface() -> some View {
        background(Color.primary.opacity(0.055))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.09)) }
    }
}

struct MetadataSettingsView: View {
    @AppStorage("metadata.defaultArtist") private var defaultArtist = "wake up fall"
    @AppStorage("metadata.filenameTemplate") private var filenameTemplate = "{track} {group} - {title} {year}"
    @AppStorage("metadata.mp3Mode") private var mp3Mode = MP3EncodingMode.cbr.rawValue
    @AppStorage("metadata.mp3Bitrate") private var mp3Bitrate = MP3Bitrate.kbps320.rawValue
    @AppStorage("metadata.mp3VBRQuality") private var mp3VBRQuality = MP3VBRQuality.v0.rawValue
    @AppStorage("metadata.mp3SampleRate") private var mp3SampleRate = MP3SampleRate.source.rawValue

    var body: some View {
        Form {
            Section("Métadonnées audio") {
                TextField("Artiste par défaut", text: $defaultArtist)
                TextField("Format du nom de fichier", text: $filenameTemplate)
                Text("Tokens : {track} {group} {title} {album} {year} {bpm}")
                    .font(.caption).foregroundStyle(.secondary)
                LabeledContent("Année par défaut", value: String(Calendar.current.component(.year, from: Date())))
                Text("L’année suit automatiquement l’année courante.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Conversion WAV vers MP3") {
                Picker("Mode", selection: $mp3Mode) {
                    ForEach(MP3EncodingMode.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                if mp3Mode == MP3EncodingMode.cbr.rawValue {
                    Picker("Débit", selection: $mp3Bitrate) {
                        ForEach(MP3Bitrate.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                } else {
                    Picker("Qualité VBR", selection: $mp3VBRQuality) {
                        ForEach(MP3VBRQuality.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                }
                Picker("Fréquence", selection: $mp3SampleRate) {
                    ForEach(MP3SampleRate.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                LabeledContent("Canaux", value: "Joint stereo")
                LabeledContent("Qualité d’encodage", value: "Maximale")
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 560, height: 520)
    }
}
