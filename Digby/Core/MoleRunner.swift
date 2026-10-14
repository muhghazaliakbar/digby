import Foundation

/// One line of output from a `mo` process, with ANSI escapes stripped.
nonisolated struct OutputLine: Sendable, Equatable {
    var text: String
    var isError: Bool
}

/// A running `mo` invocation. Streams stdout/stderr line by line and supports SIGINT cancellation.
nonisolated final class MoleProcess: @unchecked Sendable {
    let arguments: [String]
    let lines: AsyncStream<OutputLine>
    private let continuation: AsyncStream<OutputLine>.Continuation
    private let process = Process()
    private let lock = NSLock()
    private var buffers: [Bool: Data] = [false: Data(), true: Data()]
    private var openStreams = 2
    private var exitWaiters: [CheckedContinuation<Int32, Never>] = []
    private var exitStatus: Int32?
    private(set) var wasCancelled = false

    init(executable: URL, arguments: [String], environment: [String: String], stdin: Data?) {
        self.arguments = arguments
        (lines, continuation) = AsyncStream.makeStream(of: OutputLine.self, bufferingPolicy: .unbounded)
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())

        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        if let stdin {
            let input = Pipe()
            process.standardInput = input
            input.fileHandleForWriting.write(stdin)
            try? input.fileHandleForWriting.close()
        } else {
            process.standardInput = FileHandle.nullDevice
        }

        for (pipe, isError) in [(out, false), (err, true)] {
            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard let self else { return }
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    self.finishStream(isError: isError)
                } else {
                    self.consume(data, isError: isError)
                }
            }
        }
        process.terminationHandler = { [weak self] p in
            self?.resolveExit(p.terminationStatus)
        }
    }

    func start() throws {
        try process.run()
    }

    /// Sends SIGINT, like pressing ⌃C in a terminal.
    func cancel() {
        lock.lock()
        wasCancelled = true
        lock.unlock()
        if process.isRunning { process.interrupt() }
    }

    var isRunning: Bool { process.isRunning }

    /// Waits for both pipes to drain and the process to exit.
    func waitForExit() async -> Int32 {
        await withCheckedContinuation { cont in
            lock.lock()
            if let status = exitStatus, openStreams == 0 {
                lock.unlock()
                cont.resume(returning: status)
            } else {
                exitWaiters.append(cont)
                lock.unlock()
            }
        }
    }

    // MARK: Internals

    private func consume(_ data: Data, isError: Bool) {
        lock.lock()
        var buffer = buffers[isError, default: Data()]
        buffer.append(data)
        var emitted: [String] = []
        while let idx = buffer.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
            let lineData = buffer[buffer.startIndex..<idx]
            buffer.removeSubrange(buffer.startIndex...idx)
            emitted.append(String(decoding: lineData, as: UTF8.self))
        }
        buffers[isError] = buffer
        lock.unlock()
        for raw in emitted {
            let clean = ANSI.strip(raw)
            if !clean.trimmingCharacters(in: .whitespaces).isEmpty {
                continuation.yield(OutputLine(text: clean, isError: isError))
            }
        }
    }

    private func finishStream(isError: Bool) {
        lock.lock()
        let rest = buffers[isError] ?? Data()
        buffers[isError] = Data()
        lock.unlock()
        if !rest.isEmpty {
            let clean = ANSI.strip(String(decoding: rest, as: UTF8.self))
            if !clean.trimmingCharacters(in: .whitespaces).isEmpty {
                continuation.yield(OutputLine(text: clean, isError: isError))
            }
        }
        lock.lock()
        openStreams -= 1
        lock.unlock()
        resolveIfDone()
    }

    private func resolveExit(_ status: Int32) {
        lock.lock()
        exitStatus = status
        lock.unlock()
        resolveIfDone()
    }

    private func resolveIfDone() {
        lock.lock()
        guard let status = exitStatus, openStreams == 0 else {
            lock.unlock()
            return
        }
        let waiters = exitWaiters
        exitWaiters = []
        lock.unlock()
        continuation.finish()
        waiters.forEach { $0.resume(returning: status) }
    }
}

nonisolated enum ANSI {
    private static let pattern = try! NSRegularExpression(
        pattern: "\u{1B}\\[[0-9;?]*[ -/]*[@-~]|\u{1B}\\][^\u{07}]*\u{07}|\u{1B}[()][A-Z0-9]|\u{1B}[=>78]"
    )

    static func strip(_ s: String) -> String {
        let range = NSRange(s.startIndex..., in: s)
        return pattern.stringByReplacingMatches(in: s, range: range, withTemplate: "")
            .replacingOccurrences(of: "\u{07}", with: "")
    }
}

enum MoleError: LocalizedError {
    case notInstalled

    var errorDescription: String? { "The mo binary could not be found." }
}

/// Launches the `mo` binary. The app never reimplements Mole's cleaning logic.
actor MoleRunner {
    static let shared = MoleRunner()
    static let pathDefaultsKey = "moBinaryPath"

    /// Candidate locations, checked in order after a user-picked path.
    nonisolated static let candidates: [String] = [
        "/opt/homebrew/bin/mo",
        "/usr/local/bin/mo",
        NSHomeDirectory() + "/.local/bin/mo",
        NSHomeDirectory() + "/bin/mo",
        "/opt/homebrew/bin/mole",
        "/usr/local/bin/mole",
        "/run/current-system/sw/bin/mo",
        NSHomeDirectory() + "/.nix-profile/bin/mo",
    ]

    nonisolated static func locate() -> URL? {
        let fm = FileManager.default
        if let custom = UserDefaults.standard.string(forKey: pathDefaultsKey), fm.isExecutableFile(atPath: custom) {
            return URL(fileURLWithPath: custom)
        }
        return candidates.first(where: { fm.isExecutableFile(atPath: $0) }).map(URL.init(fileURLWithPath:))
    }

    nonisolated static var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        let extra = ["/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin", NSHomeDirectory() + "/.local/bin"]
        let path = (extra + (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin").split(separator: ":").map(String.init))
        var seen = Set<String>()
        env["PATH"] = path.filter { seen.insert($0).inserted }.joined(separator: ":")
        env["TERM"] = "dumb"
        env["NO_COLOR"] = "1"
        env["CLICOLOR"] = "0"
        env["COLUMNS"] = "160"
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        env["HOME"] = NSHomeDirectory()
        return env
    }

    /// Starts `mo <arguments>` and returns the live process.
    func start(_ arguments: [String], stdin: String? = nil, extraEnv: [String: String] = [:]) throws -> MoleProcess {
        guard let url = Self.locate() else { throw MoleError.notInstalled }
        var env = Self.environment
        extraEnv.forEach { env[$0.key] = $0.value }
        let proc = MoleProcess(executable: url, arguments: arguments, environment: env, stdin: stdin.map { Data($0.utf8) })
        try proc.start()
        return proc
    }

    /// Runs to completion and returns stdout (stderr lines are discarded).
    func capture(_ arguments: [String]) async throws -> (stdout: String, status: Int32) {
        let proc = try start(arguments)
        var out: [String] = []
        for await line in proc.lines where !line.isError { out.append(line.text) }
        return (out.joined(separator: "\n"), await proc.waitForExit())
    }

    /// Runs and returns raw stdout bytes, unsplit — used for JSON commands.
    nonisolated func captureData(_ arguments: [String]) async throws -> (Data, Int32) {
        guard let url = Self.locate() else { throw MoleError.notInstalled }
        let env = Self.environment
        return try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = url
            process.arguments = arguments
            process.environment = env
            process.standardInput = FileHandle.nullDevice
            let out = Pipe()
            process.standardOutput = out
            process.standardError = FileHandle.nullDevice
            try process.run()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (data, process.terminationStatus)
        }.value
    }
}
