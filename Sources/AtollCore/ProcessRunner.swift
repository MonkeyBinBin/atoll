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
    }

    enum Failure: Error, Equatable {
        case couldNotStart(String)
        /// Still running after the timeout; it was sent SIGTERM.
        case timedOut
    }

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
        do { try process.run() } catch { throw Failure.couldNotStart("\(error)") }
        if let timeout {
            guard exited.wait(timeout: .now() + timeout) == .success else {
                process.terminate()
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
                    timeout: TimeInterval? = nil, qos: DispatchQoS.QoSClass = .userInitiated) async throws -> Output {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: qos).async {
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
                throw Failure.couldNotStart("can't create \(url.path)")
            }
            handle = try FileHandle(forWritingTo: url)
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
