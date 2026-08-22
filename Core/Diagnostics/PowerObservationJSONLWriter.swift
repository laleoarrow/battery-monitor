#if DEBUG

import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

enum PowerObservationAppendResult: Equatable, Sendable {
    case written
    case fileLimitReached
}

enum PowerObservationWriterError: Error, Equatable {
    case alreadyFinalized
    case unsafeOutputDirectory
    case outputExists
    case cannotCreate
    case writeFailed
    case syncFailed
    case renameFailed
}

enum PowerObservationEncodingError: Error, Equatable {
    case failed
}

final class PowerObservationJSONLWriter {
    static let defaultMaximumFileBytes = 16 * 1024 * 1024
    static let defaultMaximumDirectoryBytes = 64 * 1024 * 1024
    static let defaultCleanupTargetBytes = 48 * 1024 * 1024
    static let reservedFooterBytes = 1024
    static let filePrefix = "wattson-power-v1-"

    let outputDirectory: URL
    private(set) var partialURLForTest: URL
    private(set) var finalURLForTest: URL
    private(set) var finalizedURL: URL?

    private let maximumFileBytes: Int
    private let maximumDirectoryBytes: Int
    private let cleanupTargetBytes: Int
    private let encoder: JSONEncoder
    private var directoryFD: Int32 = -1
    private var fileFD: Int32 = -1
    private var partialName = ""
    private var finalName = ""
    private var currentBytes: UInt64 = 0
    private var samplesWritten: UInt64 = 0
    private var recordsSinceSync = 0
    private var lastSyncNanoseconds: UInt64
    private var finalized = false

    init(
        outputDirectory: URL,
        header: PowerObservationTraceHeader,
        maximumFileBytes: Int =
            PowerObservationJSONLWriter.defaultMaximumFileBytes,
        maximumDirectoryBytes: Int =
            PowerObservationJSONLWriter.defaultMaximumDirectoryBytes,
        cleanupTargetBytes: Int =
            PowerObservationJSONLWriter.defaultCleanupTargetBytes
    ) throws {
        guard maximumFileBytes > Self.reservedFooterBytes,
              maximumDirectoryBytes >= maximumFileBytes,
              cleanupTargetBytes >= 0,
              cleanupTargetBytes <= maximumDirectoryBytes else {
            throw PowerObservationWriterError.cannotCreate
        }
        guard Self.isSafeScenario(header.scenario) else {
            throw PowerObservationWriterError.cannotCreate
        }

        self.outputDirectory = outputDirectory
        self.maximumFileBytes = maximumFileBytes
        self.maximumDirectoryBytes = maximumDirectoryBytes
        self.cleanupTargetBytes = cleanupTargetBytes
        partialURLForTest = outputDirectory
        finalURLForTest = outputDirectory
        encoder = JSONEncoder()
        encoder.outputFormatting = [
            .sortedKeys,
            .withoutEscapingSlashes,
        ]
        lastSyncNanoseconds = Self.monotonicNow()

        try Self.prepareOutputDirectory(outputDirectory)
        let openedDirectory = open(
            outputDirectory.path,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard openedDirectory >= 0 else {
            throw PowerObservationWriterError.unsafeOutputDirectory
        }
        directoryFD = openedDirectory

        do {
            try Self.validateOpenedDirectory(openedDirectory)
            try Self.cleanupDirectory(
                directoryFD: openedDirectory,
                cleanupTargetBytes: cleanupTargetBytes
            )
            let totalAfterCleanup = try Self.directoryCaptureBytes(
                directoryFD: openedDirectory
            )
            guard totalAfterCleanup <= cleanupTargetBytes,
                  totalAfterCleanup + maximumFileBytes
                    <= maximumDirectoryBytes else {
                throw PowerObservationWriterError.unsafeOutputDirectory
            }

            let base = Self.filePrefix
                + header.scenario
                + "-\(header.startedContinuousNanoseconds)"
            let opened = try Self.createExclusiveCaptureFile(
                directoryFD: openedDirectory,
                base: base,
                outputDirectory: outputDirectory
            )
            fileFD = opened.fd
            partialName = opened.partialName
            finalName = opened.finalName
            partialURLForTest = outputDirectory
                .appendingPathComponent(opened.partialName)
            finalURLForTest = outputDirectory
                .appendingPathComponent(opened.finalName)

            guard fchmod(fileFD, mode_t(0o600)) == 0 else {
                throw PowerObservationWriterError.cannotCreate
            }
            let headerLine = try encodedLine(
                PowerObservationTraceRecord(header: header)
            )
            guard headerLine.count + Self.reservedFooterBytes
                    <= maximumFileBytes else {
                throw PowerObservationWriterError.cannotCreate
            }
            try writeLine(headerLine)
        } catch {
            if fileFD >= 0 { close(fileFD) }
            fileFD = -1
            close(openedDirectory)
            directoryFD = -1
            throw error
        }
    }

    deinit {
        if fileFD >= 0 { close(fileFD) }
        if directoryFD >= 0 { close(directoryFD) }
    }

    func append(
        _ observation: RawPowerObservation
    ) throws -> PowerObservationAppendResult {
        guard !finalized else {
            throw PowerObservationWriterError.alreadyFinalized
        }
        let line: Data
        do {
            line = try encodedLine(
                PowerObservationTraceRecord(sample: observation)
            )
        } catch {
            throw PowerObservationEncodingError.failed
        }

        let projected = currentBytes
            + UInt64(line.count)
            + UInt64(Self.reservedFooterBytes)
        guard projected <= UInt64(maximumFileBytes) else {
            _ = try finalize(
                termination: .sizeLimit,
                terminationSignal: nil,
                fatalErrorCode: nil
            )
            return .fileLimitReached
        }

        try writeLine(line)
        samplesWritten += 1
        try syncIfNeeded()
        return .written
    }

    func finalize(
        termination: TraceTermination,
        terminationSignal: Int32? = nil,
        fatalErrorCode: String? = nil
    ) throws -> URL {
        guard !finalized else {
            throw PowerObservationWriterError.alreadyFinalized
        }
        finalized = true

        let footerLine: Data
        do {
            footerLine = try stableFooterLine(
                termination: termination,
                terminationSignal: terminationSignal,
                fatalErrorCode: fatalErrorCode
            )
        } catch {
            throw PowerObservationWriterError.writeFailed
        }

        do {
            try writeLine(footerLine)
            guard fsync(fileFD) == 0 else {
                throw PowerObservationWriterError.syncFailed
            }
            guard close(fileFD) == 0 else {
                fileFD = -1
                throw PowerObservationWriterError.writeFailed
            }
            fileFD = -1
            try Self.noReplaceRename(
                from: partialName,
                to: finalName,
                directoryFD: directoryFD
            )
            guard fsync(directoryFD) == 0 else {
                throw PowerObservationWriterError.syncFailed
            }
            finalizedURL = finalURLForTest
            return finalURLForTest
        } catch {
            if fileFD >= 0 {
                _ = close(fileFD)
                fileFD = -1
            }
            throw error
        }
    }

    static func recoverEligiblePartials(
        in outputDirectory: URL
    ) throws -> [URL] {
        try prepareOutputDirectory(outputDirectory)
        let directoryFD = open(
            outputDirectory.path,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard directoryFD >= 0 else {
            throw PowerObservationWriterError.unsafeOutputDirectory
        }
        var directoryIsOpen = true

        do {
            try validateOpenedDirectory(directoryFD)
            try cleanupDirectory(
                directoryFD: directoryFD,
                cleanupTargetBytes: defaultCleanupTargetBytes
            )
            var currentDirectoryBytes = try directoryCaptureBytes(
                directoryFD: directoryFD
            )
            let directoryEntries = try safeDirectoryEntries(
                directoryFD: directoryFD
            )

            // A crash may leave the bounded recovery staging file behind. It
            // deliberately ends in `.partial`, so the directory budget counts
            // it. Never overwrite or recursively recover it: surface the
            // collision so the caller can preserve the evidence for review.
            if directoryEntries.contains(where: { entry in
                entry.name.hasPrefix(filePrefix)
                    && entry.name.hasSuffix(".recovered.partial")
                    && entry.isRegular
                    && !entry.isSymbolicLink
                    && entry.owner == geteuid()
            }) {
                throw PowerObservationWriterError.outputExists
            }

            var recovered: [URL] = []
            for entry in directoryEntries {
                guard entry.name.hasPrefix(filePrefix),
                      entry.name.hasSuffix(".partial"),
                      !entry.name.hasSuffix(".recovered.partial"),
                      entry.isRegular,
                      !entry.isSymbolicLink,
                      entry.owner == geteuid(),
                      entry.size <= UInt64(defaultMaximumFileBytes) else {
                    continue
                }

                let inputFD = openat(
                    directoryFD,
                    entry.name,
                    O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK
                )
                guard inputFD >= 0 else {
                    if errno == ELOOP {
                        throw PowerObservationWriterError.unsafeOutputDirectory
                    }
                    throw PowerObservationWriterError.writeFailed
                }
                var inputIsOpen = true
                let data: Data
                do {
                    var inputStatus = stat()
                    guard fstat(inputFD, &inputStatus) == 0 else {
                        throw PowerObservationWriterError.writeFailed
                    }
                    guard isRegular(inputStatus),
                          inputStatus.st_uid == geteuid(),
                          inputStatus.st_size >= 0,
                          UInt64(inputStatus.st_size)
                            <= UInt64(defaultMaximumFileBytes) else {
                        throw PowerObservationWriterError.unsafeOutputDirectory
                    }
                    data = try readAll(
                        fd: inputFD,
                        maximum: Int(inputStatus.st_size)
                    )
                    let inputCloseResult = close(inputFD)
                    inputIsOpen = false
                    guard inputCloseResult == 0 else {
                        throw PowerObservationWriterError.writeFailed
                    }
                } catch {
                    if inputIsOpen {
                        let inputCloseResult = close(inputFD)
                        inputIsOpen = false
                        guard inputCloseResult == 0 else {
                            throw PowerObservationWriterError.writeFailed
                        }
                    }
                    throw error
                }

                guard let lastNewline = data.lastIndex(of: 0x0A) else {
                    continue
                }
                let complete = Data(data[...lastNewline])
                guard !complete.isEmpty else { continue }

                let stem = String(entry.name.dropLast(".partial".count))
                let recoveredName = stem + ".recovered.jsonl"
                guard !pathExistsNoFollow(
                    directoryFD: directoryFD,
                    name: recoveredName
                ) else {
                    // A completed recovery is the one collision that may be
                    // skipped; the original partial remains untouched.
                    continue
                }
                let (projectedDirectoryBytes, overflow) =
                    currentDirectoryBytes.addingReportingOverflow(
                        complete.count
                    )
                guard !overflow,
                      projectedDirectoryBytes
                        <= defaultMaximumDirectoryBytes else {
                    throw PowerObservationWriterError.unsafeOutputDirectory
                }

                // The staging file is counted by the existing `.partial`
                // budget rules, which bounds amplification even across a crash.
                let temporaryName = stem + ".recovered.partial"
                let outputFD = openat(
                    directoryFD,
                    temporaryName,
                    O_WRONLY | O_CREAT | O_EXCL
                        | O_NOFOLLOW | O_CLOEXEC,
                    mode_t(0o600)
                )
                guard outputFD >= 0 else {
                    if errno == EEXIST || errno == ELOOP {
                        throw PowerObservationWriterError.outputExists
                    }
                    throw PowerObservationWriterError.cannotCreate
                }
                var outputCreated = true
                var outputIsOpen = true
                do {
                    guard fchmod(outputFD, mode_t(0o600)) == 0 else {
                        throw PowerObservationWriterError.cannotCreate
                    }
                    try writeAll(complete, to: outputFD)
                    guard fsync(outputFD) == 0 else {
                        throw PowerObservationWriterError.syncFailed
                    }
                    let closeResult = close(outputFD)
                    outputIsOpen = false
                    guard closeResult == 0 else {
                        throw PowerObservationWriterError.writeFailed
                    }
                    try noReplaceRename(
                        from: temporaryName,
                        to: recoveredName,
                        directoryFD: directoryFD
                    )
                    outputCreated = false
                    currentDirectoryBytes = projectedDirectoryBytes
                    guard fsync(directoryFD) == 0 else {
                        throw PowerObservationWriterError.syncFailed
                    }
                    recovered.append(
                        outputDirectory.appendingPathComponent(recoveredName)
                    )
                } catch {
                    var cleanupError: PowerObservationWriterError?
                    if outputIsOpen {
                        let closeResult = close(outputFD)
                        outputIsOpen = false
                        if closeResult != 0 {
                            cleanupError = .writeFailed
                        }
                    }
                    if outputCreated,
                       unlinkat(directoryFD, temporaryName, 0) != 0,
                       errno != ENOENT {
                        cleanupError = .writeFailed
                    }
                    if let cleanupError {
                        throw cleanupError
                    }
                    if (error as? PowerObservationWriterError)
                            == .outputExists {
                        // The final destination appeared after the preflight.
                        // Preserve the source partial and skip this collision.
                        continue
                    }
                    throw error
                }
            }

            let result = recovered.sorted {
                $0.lastPathComponent < $1.lastPathComponent
            }
            let directoryCloseResult = close(directoryFD)
            directoryIsOpen = false
            guard directoryCloseResult == 0 else {
                throw PowerObservationWriterError.writeFailed
            }
            return result
        } catch {
            if directoryIsOpen {
                let directoryCloseResult = close(directoryFD)
                directoryIsOpen = false
                guard directoryCloseResult == 0 else {
                    throw PowerObservationWriterError.writeFailed
                }
            }
            throw error
        }
    }

    private func encodedLine<T: Encodable>(_ value: T) throws -> Data {
        var data = try encoder.encode(value)
        data.append(0x0A)
        return data
    }

    private func stableFooterLine(
        termination: TraceTermination,
        terminationSignal: Int32?,
        fatalErrorCode: String?
    ) throws -> Data {
        var expectedBytes = currentBytes
        var line = Data()
        let ended = Self.monotonicNow()
        for _ in 0..<8 {
            let footer = PowerObservationTraceFooter(
                termination: termination,
                samplesWritten: samplesWritten,
                bytesWritten: expectedBytes,
                endedContinuousNanoseconds: ended,
                terminationSignal: terminationSignal,
                fatalErrorCode: fatalErrorCode
            )
            line = try encodedLine(
                PowerObservationTraceRecord(footer: footer)
            )
            let next = currentBytes + UInt64(line.count)
            if next == expectedBytes { return line }
            expectedBytes = next
        }
        return line
    }

    private func writeLine(_ data: Data) throws {
        try Self.writeAll(data, to: fileFD)
        currentBytes += UInt64(data.count)
        recordsSinceSync += 1
    }

    private func syncIfNeeded() throws {
        let now = Self.monotonicNow()
        let elapsed = now >= lastSyncNanoseconds
            ? now - lastSyncNanoseconds : 0
        guard recordsSinceSync >= 16
                || elapsed >= 1_000_000_000 else {
            return
        }
        guard fsync(fileFD) == 0 else {
            throw PowerObservationWriterError.syncFailed
        }
        recordsSinceSync = 0
        lastSyncNanoseconds = now
    }

    private static func createExclusiveCaptureFile(
        directoryFD: Int32,
        base: String,
        outputDirectory: URL
    ) throws -> (fd: Int32, partialName: String, finalName: String) {
        for suffix in 0...99 {
            let numbered = suffix == 0 ? base : "\(base)-\(suffix)"
            let partial = numbered + ".partial"
            let final = numbered + ".jsonl"
            if pathExistsNoFollow(directoryFD: directoryFD, name: final) {
                continue
            }
            let fd = openat(
                directoryFD,
                partial,
                O_WRONLY | O_CREAT | O_EXCL
                    | O_NOFOLLOW | O_CLOEXEC,
                mode_t(0o600)
            )
            if fd >= 0 {
                return (fd, partial, final)
            }
            if errno == EEXIST || errno == ELOOP { continue }
            throw PowerObservationWriterError.cannotCreate
        }
        throw PowerObservationWriterError.outputExists
    }

    private static func prepareOutputDirectory(_ directory: URL) throws {
        let path = directory.path
        var status = stat()
        if lstat(path, &status) == 0 {
            guard !isSymbolicLink(status),
                  isDirectory(status),
                  status.st_uid == geteuid(),
                  access(path, W_OK | X_OK) == 0 else {
                throw PowerObservationWriterError.unsafeOutputDirectory
            }
            return
        }
        guard errno == ENOENT else {
            throw PowerObservationWriterError.unsafeOutputDirectory
        }
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            throw PowerObservationWriterError.cannotCreate
        }
        guard lstat(path, &status) == 0,
              !isSymbolicLink(status),
              isDirectory(status),
              status.st_uid == geteuid(),
              chmod(path, mode_t(0o700)) == 0 else {
            throw PowerObservationWriterError.unsafeOutputDirectory
        }
    }

    private static func cleanupDirectory(
        directoryFD: Int32,
        cleanupTargetBytes: Int
    ) throws {
        var entries = try safeDirectoryEntries(
            directoryFD: directoryFD
        )
        var total = entries.reduce(UInt64(0)) { partial, entry in
            guard isCaptureFileName(entry.name),
                  entry.isRegular,
                  !entry.isSymbolicLink,
                  entry.owner == geteuid() else {
                return partial
            }
            return partial + entry.size
        }
        guard total > UInt64(cleanupTargetBytes) else { return }

        entries = entries.filter { entry in
            entry.name.hasPrefix(filePrefix)
                && (entry.name.hasSuffix(".jsonl")
                    || entry.name.hasSuffix(".recovered.jsonl"))
                && !entry.name.hasSuffix(".partial")
                && entry.isRegular
                && !entry.isSymbolicLink
                && entry.owner == geteuid()
        }.sorted {
            if $0.modificationSeconds != $1.modificationSeconds {
                return $0.modificationSeconds < $1.modificationSeconds
            }
            if $0.modificationNanoseconds
                    != $1.modificationNanoseconds {
                return $0.modificationNanoseconds
                    < $1.modificationNanoseconds
            }
            return $0.name < $1.name
        }

        for entry in entries where total > UInt64(cleanupTargetBytes) {
            guard unlinkat(directoryFD, entry.name, 0) == 0 else {
                throw PowerObservationWriterError.unsafeOutputDirectory
            }
            total = total >= entry.size ? total - entry.size : 0
        }
        guard total <= UInt64(cleanupTargetBytes) else {
            throw PowerObservationWriterError.unsafeOutputDirectory
        }
    }

    private static func directoryCaptureBytes(
        directoryFD: Int32
    ) throws -> Int {
        let entries = try safeDirectoryEntries(
            directoryFD: directoryFD
        )
        let value = entries.reduce(UInt64(0)) { partial, entry in
            guard isCaptureFileName(entry.name),
                  entry.isRegular,
                  !entry.isSymbolicLink,
                  entry.owner == geteuid() else {
                return partial
            }
            return partial + entry.size
        }
        guard value <= UInt64(Int.max) else {
            throw PowerObservationWriterError.unsafeOutputDirectory
        }
        return Int(value)
    }

    private static func isCaptureFileName(_ name: String) -> Bool {
        guard name.hasPrefix(filePrefix) else { return false }
        return name.hasSuffix(".jsonl")
            || name.hasSuffix(".recovered.jsonl")
            || name.hasSuffix(".partial")
    }

    private static func isSafeScenario(_ value: String) -> Bool {
        guard (1...48).contains(value.utf8.count) else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 48...57, 65...90, 97...122:
                return true
            case 45, 46, 95:
                return true
            default:
                return false
            }
        }
    }

    private struct SafeDirectoryEntry {
        let name: String
        let size: UInt64
        let owner: uid_t
        let modificationSeconds: Int64
        let modificationNanoseconds: Int64
        let isRegular: Bool
        let isSymbolicLink: Bool
    }

    private static func safeDirectoryEntries(
        directoryFD: Int32
    ) throws -> [SafeDirectoryEntry] {
        let scanFD = openat(
            directoryFD,
            ".",
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard scanFD >= 0 else {
            throw PowerObservationWriterError.unsafeOutputDirectory
        }
        guard let stream = fdopendir(scanFD) else {
            let scanCloseResult = close(scanFD)
            guard scanCloseResult == 0 else {
                throw PowerObservationWriterError.unsafeOutputDirectory
            }
            throw PowerObservationWriterError.unsafeOutputDirectory
        }
        var streamIsOpen = true

        do {
            var entries: [SafeDirectoryEntry] = []
            while true {
                errno = 0
                guard let pointer = readdir(stream) else {
                    guard errno == 0 else {
                        throw PowerObservationWriterError
                            .unsafeOutputDirectory
                    }
                    break
                }

                var rawEntry = pointer.pointee
                let nameCapacity = MemoryLayout.size(
                    ofValue: rawEntry.d_name
                )
                let name = withUnsafePointer(to: &rawEntry.d_name) {
                    namePointer in
                    namePointer.withMemoryRebound(
                        to: CChar.self,
                        capacity: nameCapacity
                    ) {
                        String(cString: $0)
                    }
                }
                guard name != ".", name != ".." else { continue }

                var status = stat()
                guard fstatat(
                    directoryFD,
                    name,
                    &status,
                    AT_SYMLINK_NOFOLLOW
                ) == 0 else {
                    if errno == ENOENT { continue }
                    throw PowerObservationWriterError
                        .unsafeOutputDirectory
                }
                let size = status.st_size < 0
                    ? 0 : UInt64(status.st_size)
#if canImport(Darwin)
                let modifiedSeconds = Int64(status.st_mtimespec.tv_sec)
                let modifiedNanoseconds = Int64(status.st_mtimespec.tv_nsec)
#else
                let modifiedSeconds = Int64(status.st_mtim.tv_sec)
                let modifiedNanoseconds = Int64(status.st_mtim.tv_nsec)
#endif
                entries.append(SafeDirectoryEntry(
                    name: name,
                    size: size,
                    owner: status.st_uid,
                    modificationSeconds: modifiedSeconds,
                    modificationNanoseconds: modifiedNanoseconds,
                    isRegular: Self.isRegular(status),
                    isSymbolicLink: Self.isSymbolicLink(status)
                ))
            }

            let streamCloseResult = closedir(stream)
            streamIsOpen = false
            guard streamCloseResult == 0 else {
                throw PowerObservationWriterError.unsafeOutputDirectory
            }
            return entries
        } catch {
            if streamIsOpen {
                let streamCloseResult = closedir(stream)
                streamIsOpen = false
                guard streamCloseResult == 0 else {
                    throw PowerObservationWriterError.unsafeOutputDirectory
                }
            }
            throw error
        }
    }

    private static func validateOpenedDirectory(
        _ directoryFD: Int32
    ) throws {
        var status = stat()
        guard fstat(directoryFD, &status) == 0,
              isDirectory(status),
              status.st_uid == geteuid(),
              faccessat(
                directoryFD,
                ".",
                W_OK | X_OK,
                AT_EACCESS
              ) == 0 else {
            throw PowerObservationWriterError.unsafeOutputDirectory
        }
    }

    private static func isDirectory(_ status: stat) -> Bool {
        (status.st_mode & S_IFMT) == S_IFDIR
    }

    private static func isRegular(_ status: stat) -> Bool {
        (status.st_mode & S_IFMT) == S_IFREG
    }

    private static func isSymbolicLink(_ status: stat) -> Bool {
        (status.st_mode & S_IFMT) == S_IFLNK
    }

    private static func pathExistsNoFollow(
        directoryFD: Int32,
        name: String
    ) -> Bool {
        var status = stat()
        return fstatat(
            directoryFD,
            name,
            &status,
            AT_SYMLINK_NOFOLLOW
        ) == 0
    }

    private static func writeAll(
        _ data: Data,
        to fd: Int32
    ) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            var offset = 0
            while offset < rawBuffer.count {
                let count = write(
                    fd,
                    base.advanced(by: offset),
                    rawBuffer.count - offset
                )
                if count > 0 {
                    offset += count
                } else if count < 0, errno == EINTR {
                    continue
                } else {
                    throw PowerObservationWriterError.writeFailed
                }
            }
        }
    }

    private static func readAll(
        fd: Int32,
        maximum: Int
    ) throws -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while data.count < maximum {
            let remaining = maximum - data.count
            let count = read(fd, &buffer, min(buffer.count, remaining))
            if count > 0 {
                data.append(contentsOf: buffer.prefix(count))
            } else if count == 0 {
                return data
            } else if errno == EINTR {
                continue
            } else {
                throw PowerObservationWriterError.writeFailed
            }
        }
        return data
    }

    private static func noReplaceRename(
        from source: String,
        to destination: String,
        directoryFD: Int32
    ) throws {
#if canImport(Darwin)
        let result = renameatx_np(
            directoryFD,
            source,
            directoryFD,
            destination,
            UInt32(RENAME_EXCL)
        )
        guard result == 0 else {
            if errno == EEXIST { throw PowerObservationWriterError.outputExists }
            throw PowerObservationWriterError.renameFailed
        }
#else
        // linkat is a no-replace operation. Keeping the implementation here
        // lets synthetic writer tests run outside macOS; production macOS uses
        // renameatx_np with RENAME_EXCL above.
        guard linkat(
            directoryFD,
            source,
            directoryFD,
            destination,
            0
        ) == 0 else {
            if errno == EEXIST { throw PowerObservationWriterError.outputExists }
            throw PowerObservationWriterError.renameFailed
        }
        guard unlinkat(directoryFD, source, 0) == 0 else {
            _ = unlinkat(directoryFD, destination, 0)
            throw PowerObservationWriterError.renameFailed
        }
#endif
    }

    private static func monotonicNow() -> UInt64 {
        SystemContinuousNanosecondClock().nowContinuousNanoseconds()
    }
}

#endif
