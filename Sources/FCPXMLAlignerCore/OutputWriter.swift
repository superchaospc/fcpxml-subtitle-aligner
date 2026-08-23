import Foundation
import CryptoKit
import Darwin
#if canImport(FoundationXML)
import FoundationXML
#endif

public struct OutputResult {
    public let outputURL: URL
    public let reportURL: URL
    public let report: ChangeReport

    public init(outputURL: URL, reportURL: URL, report: ChangeReport) {
        self.outputURL = outputURL
        self.reportURL = reportURL
        self.report = report
    }
}

public enum OutputWriterError: Error, LocalizedError {
    case destinationExists(URL)
    case sourceChanged(URL)
    case invalidOutput(String)
    case finalizationLockUnavailable(URL)

    public var errorDescription: String? {
        switch self {
        case .destinationExists(let url): return "Refusing to overwrite existing output: \(url.path)"
        case .sourceChanged(let url): return "The input changed while it was being processed: \(url.path)"
        case .invalidOutput(let reason): return "The aligned output could not be validated: \(reason)"
        case .finalizationLockUnavailable(let url): return "Another finalization is in progress: \(url.path)"
        }
    }
}

/// Internal seams keep filesystem failure paths deterministic without exposing test-only API publicly.
struct OutputWriterHooks {
    var makeUUID: () -> UUID = UUID.init
    var serialize: ((FCPXMLDocument) throws -> Data)? = nil
    var observeHashedFile: (URL) -> Void = { _ in }
    var beforeFinalizationLock: () throws -> Void = {}
    var beforeFinalization: () throws -> Void = {}
    var afterFirstFinalMove: () throws -> Void = {}
    var beforeWorkspaceCleanup: () throws -> Void = {}
}

public struct OutputWriter {
    private let hooks: OutputWriterHooks

    public init() {
        hooks = OutputWriterHooks()
    }

    init(hooks: OutputWriterHooks) {
        self.hooks = hooks
    }

    public func process(input: URL, settings: AlignmentSettings) throws -> OutputResult {
        let fileManager = FileManager.default
        let inputDocument = try InputDocument(sourceURL: input)
        let sourceFingerprint = try SourceFingerprint(
            url: input,
            fileManager: fileManager,
            observeHashedFile: hooks.observeHashedFile
        )
        let parent = input.deletingLastPathComponent()
        var ownsWorkspace = false
        let workspace = try makeWorkspace(in: parent, fileManager: fileManager)
        let workspaceIdentity = try FileSystemIdentity(url: workspace)
        ownsWorkspace = true

        defer {
            try? hooks.beforeWorkspaceCleanup()
            if ownsWorkspace,
               (try? FileSystemIdentity(url: workspace)) == workspaceIdentity {
                try? fileManager.removeItem(at: workspace)
            }
        }

        let temporaryOutputURL = workspace.appendingPathComponent(
            "output.\(inputDocument.kind == .bundle ? "fcpxmld" : "fcpxml")"
        )
        let temporaryReportURL = workspace.appendingPathComponent("report.txt")
        try fileManager.copyItem(at: input, to: temporaryOutputURL)
        let copiedInput = try InputDocument(sourceURL: temporaryOutputURL)
        let document = try FCPXMLDocument(inputDocument: copiedInput)
        let sourceProjectNames = try projectNames(in: document)
        let report = try ProjectTransformer().transform(document, settings: settings)
        let transformedInvariants = InvariantSnapshot(document: document)
        try verify(
            sourceFingerprint: sourceFingerprint,
            matches: input,
            fileManager: fileManager,
            observeHashedFile: hooks.observeHashedFile
        )
        try hooks.beforeFinalizationLock()
        return try withFinalizationLock(in: parent, fileManager: fileManager) {
            let names = try destinationNames(for: input, kind: inputDocument.kind, fileManager: fileManager)
            let outputProjectNames = try updateProjects(in: document, suffix: names.projectSuffix)
            guard InvariantSnapshot(document: document) == transformedInvariants else {
                throw AlignerError.invariantViolation("Project identity updates changed protected FCPXML content.")
            }

            let serialized = try serializedData(document, sourceXMLURL: copiedInput.xmlURL)
            try serialized.write(to: copiedInput.xmlURL, options: .atomic)
            let reparsed = try FCPXMLDocument(inputDocument: InputDocument(sourceURL: temporaryOutputURL))
            guard reparsed.version == document.version else {
                throw OutputWriterError.invalidOutput("FCPXML version changed from \(document.version) to \(reparsed.version).")
            }
            guard InvariantSnapshot(document: reparsed) == transformedInvariants else {
                throw AlignerError.invariantViolation("The serialized output changed protected FCPXML content.")
            }

            let reportText = report.plainText(
                inputURL: input,
                outputURL: names.outputURL,
                reportURL: names.reportURL,
                version: document.version,
                sourceProjectNames: sourceProjectNames,
                outputProjectNames: outputProjectNames
            )
            try Data(reportText.utf8).write(to: temporaryReportURL, options: .withoutOverwriting)
            try hooks.beforeFinalization()
            try verify(
                sourceFingerprint: sourceFingerprint,
                matches: input,
                fileManager: fileManager,
                observeHashedFile: hooks.observeHashedFile
            )
            guard !fileManager.fileExists(atPath: names.outputURL.path),
                  !fileManager.fileExists(atPath: names.reportURL.path)
            else {
                throw OutputWriterError.destinationExists(
                    fileManager.fileExists(atPath: names.outputURL.path) ? names.outputURL : names.reportURL
                )
            }

            // Two renames cannot be instantaneously atomic. The owned lock prevents competing
            // tool instances, and the inode-and-fingerprint checked rollback restores no-delivery
            // end-state if the second move fails.
            let movedOutput = try ArtifactIdentity(
                url: temporaryOutputURL,
                fileManager: fileManager,
                observeHashedFile: hooks.observeHashedFile
            )
            do {
                try fileManager.moveItem(at: temporaryOutputURL, to: names.outputURL)
                try hooks.afterFirstFinalMove()
                try fileManager.moveItem(at: temporaryReportURL, to: names.reportURL)
            } catch {
                try rollbackOwnedArtifact(
                    at: names.outputURL,
                    expected: movedOutput,
                    fileManager: fileManager,
                    observeHashedFile: hooks.observeHashedFile
                )
                throw error
            }
            return OutputResult(outputURL: names.outputURL, reportURL: names.reportURL, report: report)
        }
    }

    private func destinationNames(for input: URL, kind: InputKind, fileManager: FileManager) throws -> OutputNames {
        let parent = input.deletingLastPathComponent()
        let base = input.deletingPathExtension().lastPathComponent
        let outputExtension = kind == .bundle ? "fcpxmld" : "fcpxml"
        for number in 1...10_000 {
            let suffix = number == 1 ? "-aligned" : "-aligned-\(number)"
            let output = parent.appendingPathComponent("\(base)\(suffix).\(outputExtension)")
            let report = parent.appendingPathComponent("\(base)\(suffix)-report.txt")
            if !fileManager.fileExists(atPath: output.path), !fileManager.fileExists(atPath: report.path) {
                return OutputNames(outputURL: output, reportURL: report, projectSuffix: suffix)
            }
        }
        throw OutputWriterError.invalidOutput("Could not reserve an unused sibling output name.")
    }

    private func makeWorkspace(in parent: URL, fileManager: FileManager) throws -> URL {
        for _ in 0..<64 {
            let workspace = parent.appendingPathComponent(".fcpxml-aligner-stage-\(hooks.makeUUID().uuidString)")
            do {
                try fileManager.createDirectory(at: workspace, withIntermediateDirectories: false)
                return workspace
            } catch {
                if fileManager.fileExists(atPath: workspace.path) { continue }
                throw error
            }
        }
        throw OutputWriterError.invalidOutput("Could not create an exclusive staging workspace.")
    }

    private func withFinalizationLock<Result>(
        in parent: URL,
        fileManager: FileManager,
        body: () throws -> Result
    ) throws -> Result {
        let lockURL = parent.appendingPathComponent(".fcpxml-aligner-finalize.lock")
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw OutputWriterError.finalizationLockUnavailable(lockURL)
        }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            _ = close(descriptor)
            throw OutputWriterError.finalizationLockUnavailable(lockURL)
        }
        defer {
            _ = flock(descriptor, LOCK_UN)
            _ = close(descriptor)
        }
        return try body()
    }

    private func serializedData(_ document: FCPXMLDocument, sourceXMLURL: URL) throws -> Data {
        if let serialize = hooks.serialize { return try serialize(document) }
        let source = try String(contentsOf: sourceXMLURL, encoding: .utf8)
        let beforeRoot = source.range(of: "<fcpxml")
            .map { String(source[..<$0.lowerBound]) } ?? ""
        return Data((beforeRoot + document.rootXML).utf8)
    }

    private func projectNames(in document: FCPXMLDocument) throws -> [String] {
        try document.xmlDocument.nodes(forXPath: "//project").compactMap { node in
            (node as? XMLElement)?.attribute(forName: "name")?.stringValue
        }
    }

    private func updateProjects(in document: FCPXMLDocument, suffix: String) throws -> [String] {
        try document.xmlDocument.nodes(forXPath: "//project").compactMap { $0 as? XMLElement }.map { project in
            let name = project.attribute(forName: "name")?.stringValue ?? ""
            if !name.hasSuffix(suffix) {
                project.addAttribute(XMLNode.attribute(withName: "name", stringValue: name + suffix) as! XMLNode)
            }
            project.addAttribute(XMLNode.attribute(withName: "uid", stringValue: hooks.makeUUID().uuidString) as! XMLNode)
            return project.attribute(forName: "name")?.stringValue ?? name + suffix
        }
    }
}

private struct OutputNames {
    let outputURL: URL
    let reportURL: URL
    let projectSuffix: String
}

private struct SourceFingerprint: Equatable {
    let root: FileSystemIdentity
    let xmlSHA256: Data
    let inventory: [InventoryEntry]

    init(
        url: URL,
        fileManager: FileManager,
        observeHashedFile: (URL) -> Void
    ) throws {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        root = try FileSystemIdentity(url: url)
        if values.isDirectory == true {
            let relativePaths = try fileManager.subpathsOfDirectory(atPath: url.path).sorted()
            inventory = try relativePaths.map { relativePath in
                let fileURL = url.appendingPathComponent(relativePath)
                return try InventoryEntry(relativePath: relativePath, url: fileURL)
            }
            xmlSHA256 = try sha256(of: url.appendingPathComponent("Info.fcpxml"), observe: observeHashedFile)
        } else {
            inventory = []
            xmlSHA256 = try sha256(of: url, observe: observeHashedFile)
        }
    }
}

private struct InventoryEntry: Equatable {
    let relativePath: String
    let type: FileSystemEntryType
    let size: Int64
    let modificationSeconds: Int64
    let modificationNanoseconds: Int64
    let fileID: FileSystemIdentity

    init(relativePath: String, url: URL) throws {
        var status = stat()
        guard lstat(url.path, &status) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        self.relativePath = relativePath
        switch status.st_mode & S_IFMT {
        case S_IFREG: type = .regular
        case S_IFDIR: type = .directory
        case S_IFLNK: type = .symbolicLink
        default: type = .other
        }
        size = Int64(status.st_size)
        modificationSeconds = Int64(status.st_mtimespec.tv_sec)
        modificationNanoseconds = Int64(status.st_mtimespec.tv_nsec)
        fileID = FileSystemIdentity(device: UInt64(status.st_dev), inode: UInt64(status.st_ino))
    }
}

private enum FileSystemEntryType: Equatable {
    case regular
    case directory
    case symbolicLink
    case other
}

private struct FileSystemIdentity: Equatable {
    let device: UInt64
    let inode: UInt64

    init(url: URL) throws {
        var status = stat()
        guard lstat(url.path, &status) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        self.init(device: UInt64(status.st_dev), inode: UInt64(status.st_ino))
    }

    init(device: UInt64, inode: UInt64) {
        self.device = device
        self.inode = inode
    }
}

private struct ArtifactIdentity: Equatable {
    let fileSystem: FileSystemIdentity
    let fingerprint: SourceFingerprint

    init(url: URL, fileManager: FileManager, observeHashedFile: (URL) -> Void) throws {
        fileSystem = try FileSystemIdentity(url: url)
        fingerprint = try SourceFingerprint(
            url: url,
            fileManager: fileManager,
            observeHashedFile: observeHashedFile
        )
    }
}

private func sha256(of url: URL, observe: (URL) -> Void) throws -> Data {
    observe(url)
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hasher = SHA256()
    while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
        hasher.update(data: chunk)
    }
    return Data(hasher.finalize())
}

private func verify(
    sourceFingerprint: SourceFingerprint,
    matches url: URL,
    fileManager: FileManager,
    observeHashedFile: (URL) -> Void
) throws {
    guard try SourceFingerprint(
        url: url,
        fileManager: fileManager,
        observeHashedFile: observeHashedFile
    ) == sourceFingerprint else {
        throw OutputWriterError.sourceChanged(url)
    }
}

private func rollbackOwnedArtifact(
    at url: URL,
    expected: ArtifactIdentity,
    fileManager: FileManager,
    observeHashedFile: (URL) -> Void
) throws {
    guard fileManager.fileExists(atPath: url.path) else { return }
    guard try ArtifactIdentity(
        url: url,
        fileManager: fileManager,
        observeHashedFile: observeHashedFile
    ) == expected else { return }
    try fileManager.removeItem(at: url)
}
