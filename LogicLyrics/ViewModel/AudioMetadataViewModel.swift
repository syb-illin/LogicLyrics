import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AudioMetadataViewModel: ObservableObject {
    @Published var sourceURL: URL?
    @Published var title = ""
    @Published var trackNumber = "01"
    @Published var artist = "wake up fall"
    @Published var album = ""
    @Published var genre = "Alternative"
    @Published var year = Calendar.current.component(.year, from: Date())
    @Published var bpmText = ""
    @Published var filenameTemplate = "{track} {group} - {title} {year}"
    @Published var encodingMode = MP3EncodingMode.cbr
    @Published var mp3Bitrate = MP3Bitrate.kbps320
    @Published var vbrQuality = MP3VBRQuality.v0
    @Published var mp3SampleRate = MP3SampleRate.source
    @Published var includesLyrics = false
    @Published var artworkURL: URL?
    @Published var artworkImage: NSImage?
    @Published private var artworkData: Data?
    @Published private var artworkMIMEType: String?
    @Published private(set) var technicalInfo: AudioTechnicalInfo?
    @Published private(set) var isWriting = false
    @Published private(set) var operationState = OperationState.idle
    @Published var message: String?
    @Published var errorMessage: String?
    private let inspector: any AudioInspecting
    private let metadataReader: any AudioMetadataReading
    private let metadataWriter: any AudioMetadataWriting
    private let mp3Converter: any MP3Converting
    private var operationTask: Task<Void, Never>?
    private var operationID = UUID()
    private var synchronizedProjectName = ""
    private var synchronizedBPM: Double?

    init(
        inspector: any AudioInspecting = AudioFileInspector(),
        metadataReader: any AudioMetadataReading = AudioMetadataReader(),
        metadataWriter: any AudioMetadataWriting = AudioMetadataWriter(),
        mp3Converter: any MP3Converting = MP3Converter()
    ) {
        self.inspector = inspector
        self.metadataReader = metadataReader
        self.metadataWriter = metadataWriter
        self.mp3Converter = mp3Converter
    }

    func synchronize(projectName: String, suggestedTitle: String, bpm: Double?) {
        synchronizedProjectName = projectName
        synchronizedBPM = bpm
        if title.isEmpty { title = suggestedTitle }
        if album.isEmpty { album = projectName }
        if bpmText.isEmpty, let bpm {
            bpmText = bpm.rounded() == bpm ? String(Int(bpm)) : String(format: "%.2f", bpm)
        }
        artist = UserDefaults.standard.string(forKey: "metadata.defaultArtist") ?? "wake up fall"
        filenameTemplate = UserDefaults.standard.string(forKey: "metadata.filenameTemplate")
            ?? "{track} {group} - {title} {year}"
        encodingMode = MP3EncodingMode(rawValue: UserDefaults.standard.string(forKey: "metadata.mp3Mode") ?? "") ?? .cbr
        mp3Bitrate = MP3Bitrate(rawValue: UserDefaults.standard.integer(forKey: "metadata.mp3Bitrate")) ?? .kbps320
        vbrQuality = MP3VBRQuality(rawValue: UserDefaults.standard.integer(forKey: "metadata.mp3VBRQuality")) ?? .v0
        mp3SampleRate = MP3SampleRate(rawValue: UserDefaults.standard.string(forKey: "metadata.mp3SampleRate") ?? "") ?? .source
    }

    func selectAudio() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.mp3, .wav]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadAudio(url)
    }

    func loadAudio(_ url: URL) {
        guard ["mp3", "wav", "wave"].contains(url.pathExtension.lowercased()) else {
            errorMessage = "Choisis un fichier MP3 ou WAV."
            return
        }
        sourceURL = url
        title = url.deletingPathExtension().lastPathComponent
        trackNumber = "01"
        album = synchronizedProjectName
        artist = UserDefaults.standard.string(forKey: "metadata.defaultArtist") ?? "wake up fall"
        genre = "Alternative"
        year = Calendar.current.component(.year, from: Date())
        bpmText = synchronizedBPM.map { $0.rounded() == $0 ? String(Int($0)) : String(format: "%.2f", $0) } ?? ""
        artworkURL = nil
        artworkData = nil
        artworkMIMEType = nil
        artworkImage = nil
        technicalInfo = nil
        message = nil
        errorMessage = nil
        operationTask?.cancel()
        let operationID = UUID()
        self.operationID = operationID
        operationState = .running(message: "Analyse technique et lecture de la pochette…", startedAt: Date())
        let inspector = inspector, metadataReader = metadataReader
        operationTask = Task.detached(priority: .userInitiated) { [weak self, inspector, metadataReader] in
            do {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                try Task<Never, Never>.checkCancellation()
                let result = (try inspector.inspect(url), try metadataReader.read(from: url))
                try Task<Never, Never>.checkCancellation()
                await self?.completeAudioLoad(result, url: url, operationID: operationID)
            } catch is CancellationError {
                await self?.finishOperation(operationID)
            } catch {
                await self?.failOperation("Analyse technique impossible : \(error.localizedDescription)", operationID: operationID)
            }
        }
    }

    func selectArtwork() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.jpeg, .png]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let image = NSImage(contentsOf: url) else {
            errorMessage = "Cette image ne peut pas être décodée. Choisis un PNG ou JPEG valide."
            return
        }
        artworkURL = url
        artworkImage = image
        do {
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            guard data.count <= 20 * 1_024 * 1_024 else {
                artworkData = nil
                artworkImage = nil
                errorMessage = "La pochette dépasse 20 Mo. Choisis une image optimisée."
                return
            }
            artworkData = data
        }
        catch {
            artworkData = nil
            artworkImage = nil
            errorMessage = "Lecture de la pochette impossible : \(error.localizedDescription)"
        }
        artworkMIMEType = url.pathExtension.lowercased() == "png" ? "image/png" : "image/jpeg"
    }

    func removeArtwork() {
        artworkURL = nil
        artworkImage = nil
        artworkData = nil
        artworkMIMEType = nil
    }

    func write(lyrics: String) {
        guard let sourceURL else { errorMessage = "Choisis d’abord un export Suno MP3 ou WAV."; return }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty, !cleanArtist.isEmpty else {
            errorMessage = "Le titre et l’artiste sont obligatoires."
            return
        }
        let bpm = Double(bpmText.replacingOccurrences(of: ",", with: "."))
        if !bpmText.isEmpty, bpm.map({ !(20...400).contains($0) }) ?? true {
            errorMessage = "Le BPM doit être compris entre 20 et 400."
            return
        }
        guard (1000...9999).contains(year) else { errorMessage = "L’année doit contenir quatre chiffres valides."; return }
        if let templateError = filenameTemplateError {
            errorMessage = templateError
            return
        }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = outputFilename
        panel.allowedContentTypes = [sourceURL.pathExtension.lowercased() == "mp3" ? .mp3 : .wav]
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        guard destination.standardizedFileURL != sourceURL.standardizedFileURL else {
            errorMessage = "Choisis un autre nom : le fichier original ne sera jamais remplacé."
            return
        }

        let metadata = AudioMetadata(
            title: cleanTitle, trackNumber: trackNumber.trimmingCharacters(in: .whitespacesAndNewlines),
            artist: cleanArtist,
            album: album.trimmingCharacters(in: .whitespacesAndNewlines), year: year,
            genre: genre.trimmingCharacters(in: .whitespacesAndNewlines), bpm: bpm,
            lyrics: includesLyrics ? lyrics : nil, artwork: artworkData,
            artworkMIMEType: artworkData == nil ? nil : artworkMIMEType
        )
        operationTask?.cancel()
        let operationID = UUID()
        self.operationID = operationID
        isWriting = true
        operationState = .running(message: "Écriture sécurisée des métadonnées…", startedAt: Date())
        errorMessage = nil
        message = nil
        let metadataWriter = metadataWriter
        operationTask = Task.detached(priority: .userInitiated) { [weak self, metadataWriter] in
            do {
                let sourceAccess = sourceURL.startAccessingSecurityScopedResource()
                let destinationAccess = destination.startAccessingSecurityScopedResource()
                defer {
                    if sourceAccess { sourceURL.stopAccessingSecurityScopedResource() }
                    if destinationAccess { destination.stopAccessingSecurityScopedResource() }
                }
                try metadataWriter.write(source: sourceURL, destination: destination, metadata: metadata)
                try Task<Never, Never>.checkCancellation()
                await self?.completeWrite(destination, prefix: "Fichier créé", operationID: operationID)
            } catch is CancellationError {
                await self?.finishOperation(operationID)
            } catch {
                await self?.failOperation("Écriture impossible : \(error.localizedDescription)", operationID: operationID)
            }
        }
    }

    func convertToMP3(lyrics: String) {
        guard let sourceURL, ["wav", "wave"].contains(sourceURL.pathExtension.lowercased()) else {
            errorMessage = "Choisis un fichier WAV pour effectuer la conversion MP3."
            return
        }
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Le titre et l’artiste sont obligatoires."
            return
        }
        let convertedBPM = Double(bpmText.replacingOccurrences(of: ",", with: "."))
        if !bpmText.isEmpty, convertedBPM.map({ !(20...400).contains($0) }) ?? true {
            errorMessage = "Le BPM doit être compris entre 20 et 400."
            return
        }
        guard (1000...9999).contains(year) else {
            errorMessage = "L’année doit contenir quatre chiffres valides."
            return
        }
        if let templateError = filenameTemplateError {
            errorMessage = templateError
            return
        }
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = outputFilename.replacingOccurrences(of: #"\.[^.]+$"#, with: ".mp3", options: .regularExpression)
        panel.allowedContentTypes = [.mp3]
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        guard destination.standardizedFileURL != sourceURL.standardizedFileURL else {
            errorMessage = "La destination doit être différente du fichier source."
            return
        }

        let metadata = AudioMetadata(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            trackNumber: trackNumber.trimmingCharacters(in: .whitespacesAndNewlines),
            artist: artist.trimmingCharacters(in: .whitespacesAndNewlines),
            album: album.trimmingCharacters(in: .whitespacesAndNewlines), year: year,
            genre: genre.trimmingCharacters(in: .whitespacesAndNewlines),
            bpm: convertedBPM,
            lyrics: includesLyrics ? lyrics : nil, artwork: artworkData,
            artworkMIMEType: artworkData == nil ? nil : artworkMIMEType
        )
        let settings = MP3EncodingSettings(mode: encodingMode, bitrate: mp3Bitrate, vbrQuality: vbrQuality, sampleRate: mp3SampleRate)
        UserDefaults.standard.set(encodingMode.rawValue, forKey: "metadata.mp3Mode")
        UserDefaults.standard.set(mp3Bitrate.rawValue, forKey: "metadata.mp3Bitrate")
        UserDefaults.standard.set(vbrQuality.rawValue, forKey: "metadata.mp3VBRQuality")
        UserDefaults.standard.set(mp3SampleRate.rawValue, forKey: "metadata.mp3SampleRate")
        operationTask?.cancel()
        let operationID = UUID()
        self.operationID = operationID
        isWriting = true; errorMessage = nil; message = nil
        operationState = .running(message: "Conversion WAV vers MP3 et écriture des tags…", startedAt: Date())
        let mp3Converter = mp3Converter, metadataWriter = metadataWriter
        operationTask = Task.detached(priority: .userInitiated) { [weak self, mp3Converter, metadataWriter] in
            let temporaryBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let temporaryWAV = temporaryBase.appendingPathExtension("wav")
            let temporaryMP3 = temporaryBase.appendingPathExtension("mp3")
            defer {
                try? FileManager.default.removeItem(at: temporaryWAV)
                try? FileManager.default.removeItem(at: temporaryMP3)
            }
            do {
                let sourceAccess = sourceURL.startAccessingSecurityScopedResource()
                let destinationAccess = destination.startAccessingSecurityScopedResource()
                defer {
                    if sourceAccess { sourceURL.stopAccessingSecurityScopedResource() }
                    if destinationAccess { destination.stopAccessingSecurityScopedResource() }
                }
                try FileManager.default.copyItem(at: sourceURL, to: temporaryWAV)
                try Task<Never, Never>.checkCancellation()
                try mp3Converter.convert(wav: temporaryWAV, destination: temporaryMP3, settings: settings)
                try Task<Never, Never>.checkCancellation()
                try metadataWriter.write(source: temporaryMP3, destination: destination, metadata: metadata)
                try Task<Never, Never>.checkCancellation()
                await self?.completeWrite(destination, prefix: "MP3 créé", operationID: operationID)
            } catch is CancellationError {
                await self?.finishOperation(operationID)
            } catch {
                await self?.failOperation(error.localizedDescription, operationID: operationID)
            }
        }
    }

    func cancelProcessing() {
        guard operationState.isRunning else { return }
        operationTask?.cancel()
        if case .running(_, let startedAt) = operationState {
            operationState = .running(message: "Annulation en cours…", startedAt: startedAt)
        }
    }

    var outputFilename: String {
        let ext = sourceURL?.pathExtension.lowercased() == "mp3" ? "mp3" : "wav"
        let replacements = [
            "{track}": trackNumber,
            "{group}": artist,
            "{title}": title,
            "{album}": album,
            "{year}": String(year),
            "{bpm}": bpmText
        ]
        let base = replacements.reduce(filenameTemplate) { result, item in
            result.replacingOccurrences(of: item.key, with: item.value)
        }
        let forbidden = CharacterSet(charactersIn: "/:\\").union(.controlCharacters)
        var safe = base.components(separatedBy: forbidden).joined(separator: "-")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        safe = safe.replacingOccurrences(of: #"(?i)\.(mp3|wav|wave)$"#, with: "", options: .regularExpression)
        return (safe.isEmpty ? "export-tagged" : safe) + "." + ext
    }

    private var filenameTemplateError: String? {
        let known = ["{track}", "{group}", "{title}", "{album}", "{year}", "{bpm}"]
        var remainder = filenameTemplate
        for token in known { remainder = remainder.replacingOccurrences(of: token, with: "") }
        if remainder.contains("{") || remainder.contains("}") {
            return "Le format du nom contient un token inconnu. Utilise uniquement : \(known.joined(separator: " "))."
        }
        return nil
    }

    private func completeAudioLoad(
        _ result: (AudioTechnicalInfo, ExistingAudioMetadata), url: URL, operationID: UUID
    ) {
        guard self.operationID == operationID, sourceURL == url else { return }
        technicalInfo = result.0
        let existing = result.1
        title = existing.title ?? url.deletingPathExtension().lastPathComponent
        trackNumber = existing.trackNumber ?? "01"
        artist = existing.artist ?? (UserDefaults.standard.string(forKey: "metadata.defaultArtist") ?? "wake up fall")
        album = existing.album ?? synchronizedProjectName
        year = existing.year ?? Calendar.current.component(.year, from: Date())
        genre = existing.genre ?? "Alternative"
        if let bpm = existing.bpm {
            bpmText = bpm.rounded() == bpm ? String(Int(bpm)) : String(format: "%.2f", bpm)
        }
        if let embedded = existing.artwork, embedded.data.count <= 20 * 1_024 * 1_024,
           let image = NSImage(data: embedded.data) {
            artworkData = embedded.data
            artworkMIMEType = embedded.mimeType
            artworkImage = image
        }
        finishOperation(operationID)
    }

    private func completeWrite(_ destination: URL, prefix: String, operationID: UUID) {
        guard self.operationID == operationID else { return }
        message = "\(prefix) : \(destination.lastPathComponent)"
        NSWorkspace.shared.activateFileViewerSelecting([destination])
        finishOperation(operationID)
    }

    private func failOperation(_ message: String, operationID: UUID) {
        guard self.operationID == operationID else { return }
        technicalInfo = sourceURL == nil ? nil : technicalInfo
        errorMessage = message
        finishOperation(operationID)
    }

    private func finishOperation(_ operationID: UUID) {
        guard self.operationID == operationID else { return }
        isWriting = false
        operationState = .idle
        operationTask = nil
    }
}
