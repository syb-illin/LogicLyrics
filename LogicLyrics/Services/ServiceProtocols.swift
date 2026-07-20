import Foundation

protocol LogicProjectReading: Sendable {
    func readProject(at projectURL: URL) throws -> LogicProjectReader.Result
}

protocol LogicProjectWriting: Sendable {
    func createEditedCopy(source: URL, destination: URL, alternative: String, originalText: String, editedText: String) throws
}

protocol AudioMetadataWriting: Sendable {
    func write(source: URL, destination: URL, metadata: AudioMetadata) throws
}

protocol AudioInspecting: Sendable {
    func inspect(_ url: URL) throws -> AudioTechnicalInfo
}

protocol ArtworkReading: Sendable {
    func read(from url: URL) throws -> EmbeddedArtwork?
}

protocol AudioMetadataReading: Sendable {
    func read(from url: URL) throws -> ExistingAudioMetadata
}

protocol MP3Converting: Sendable {
    func convert(wav: URL, destination: URL, settings: MP3EncodingSettings) throws
}

extension LogicProjectReader: LogicProjectReading {}
extension LogicProjectWriter: LogicProjectWriting {}
extension AudioMetadataWriter: AudioMetadataWriting {}
extension AudioFileInspector: AudioInspecting {}
extension AudioArtworkReader: ArtworkReading {}
extension AudioMetadataReader: AudioMetadataReading {}
extension MP3Converter: MP3Converting {}
