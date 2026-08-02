import AppKit
import Foundation

protocol UpdateInstalling: Sendable {
    @MainActor
    func install(_ release: UpdateRelease) throws
}

struct TerminalUpdateInstaller: UpdateInstalling {
    @MainActor
    func install(_ release: UpdateRelease) throws {
        guard let archiveURL = release.sourceArchiveURL,
              let checksumURL = release.sourceChecksumURL,
              let bundled = Bundle.main.url(forResource: "UPDATE", withExtension: "command") else {
            throw UpdateService.UpdateError.missingUpdater
        }
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.sybillin.LogicLyrics/updater", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent("UPDATE.command")
        let currentApplication = Bundle.main.bundleURL.standardizedFileURL
        guard currentApplication.pathExtension.lowercased() == "app",
              FileManager.default.isWritableFile(
                atPath: currentApplication.deletingLastPathComponent().path
              ) else {
            throw UpdateService.UpdateError.unwritableInstallation
        }
        try Data(contentsOf: bundled).write(to: executable, options: .atomic)
        try write(currentApplication.path, named: "target-path.txt", in: directory)
        try write(release.version, named: "expected-version.txt", in: directory)
        try write(archiveURL.absoluteString, named: "archive-url.txt", in: directory)
        try write(checksumURL.absoluteString, named: "checksum-url.txt", in: directory)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )
        guard NSWorkspace.shared.open(executable) else {
            throw UpdateService.UpdateError.cannotLaunch
        }
    }

    private func write(_ value: String, named name: String, in directory: URL) throws {
        try Data(value.utf8).write(
            to: directory.appendingPathComponent(name),
            options: [.atomic, .completeFileProtectionUnlessOpen]
        )
    }
}
