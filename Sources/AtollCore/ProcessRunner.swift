import Foundation

/// Runs a program to completion and captures its output. Stdout and stderr go to temporary files, not pipes:
/// a background child (gitstatusd from a login shell, a daemon a CLI starts) keeping a pipe open would block
/// reading it to EOF long after the program itself exits, and a full stderr pipe can't stall stdout.
enum ProcessRunner {
    struct Output: Equatable, Sendable {
        var status: Int32
        /// False when a signal ended it (`status` is then the signal number).
        var exited: Bool
        var stdout: Data
        var stderr: Data

        var stdoutText: String { String(decoding: stdout, as: UTF8.self) }
        var stderrText: String { String(decoding: stderr, as: UTF8.self) }
        /// What a CLI said when it failed: stderr, or stdout when stderr is empty.
        var errorText: String { stderr.isEmpty ? stdoutText : stderrText }
    }

    /// A program that can't be started throws the system's error instead.
    enum Failure: Error, Equatable {
        /// Still running after the timeout: stopped with SIGTERM, then SIGKILL if it ignored that.
        case timedOut
        /// No temporary file for its output (the temporary directory isn't writable).
        case noOutputFile(String)
    }

    /// How long a program stopped for the timeout gets to exit on SIGTERM before SIGKILL.
    static let terminationGrace: TimeInterval = 1

    /// The user's login shell, the one launches and agent CLI detection run through.
    static func loginShell() -> String {
        ProcessInfo.processInfo.environment["SHELL"].flatMap { $0.isEmpty ? nil : $0 } ?? "/bin/zsh"
    }

    /// Blocks until the program exits. `environment` nil = this process's; `timeout` nil = wait for as long as
    /// it takes. Stdin is `/dev/null`.
    static func run(_ executable: String, _ arguments: [String], environment: [String: String]? = nil,
                    timeout: TimeInterval? = nil) throws -> Output {
        let stdout = try TemporaryOutput()
        let stderr = try TemporaryOutput()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment { process.environment = environment }
        process.standardOutput = stdout.handle
        process.standardError = stderr.handle
        process.standardInput = FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        try process.run()
        if let timeout {
            guard exited.wait(timeout: .now() + timeout) == .success else {
                process.terminate()
                if exited.wait(timeout: .now() + terminationGrace) == .timedOut {
                    kill(process.processIdentifier, SIGKILL)
                    exited.wait()
                }
                throw Failure.timedOut
            }
        } else {
            exited.wait()
        }
        return Output(status: process.terminationStatus, exited: process.terminationReason == .exit,
                      stdout: stdout.contents(), stderr: stderr.contents())
    }

    /// `run` off the caller's thread.
    static func run(_ executable: String, _ arguments: [String], environment: [String: String]? = nil,
                    timeout: TimeInterval? = nil) async throws -> Output {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result { try run(executable, arguments, environment: environment, timeout: timeout) })
            }
        }
    }

    /// A temporary file the program writes to, removed when this goes away.
    private final class TemporaryOutput {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("atoll-run-\(UUID().uuidString)")
        let handle: FileHandle

        init() throws {
            guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
                throw Failure.noOutputFile(url.path)
            }
            do {
                handle = try FileHandle(forWritingTo: url)
            } catch {
                try? FileManager.default.removeItem(at: url)
                throw Failure.noOutputFile(url.path)
            }
        }

        func contents() -> Data {
            (try? Data(contentsOf: url)) ?? Data()
        }

        deinit {
            try? handle.close()
            try? FileManager.default.removeItem(at: url)
        }
    }
}
