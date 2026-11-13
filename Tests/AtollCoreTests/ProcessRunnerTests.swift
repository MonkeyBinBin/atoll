import Foundation
import Testing
@testable import AtollCore

/// Spawns real processes, so it's opt-in:
///   ATOLL_PROCESS_TESTS=1 swift test --filter ProcessRunner
@Suite("Process runner (real processes)",
       .enabled(if: ProcessInfo.processInfo.environment["ATOLL_PROCESS_TESTS"] == "1"))
struct ProcessRunnerTests {
    func sh(_ script: String, environment: [String: String]? = nil, timeout: TimeInterval? = nil) throws -> ProcessRunner.Output {
        try ProcessRunner.run("/bin/sh", ["-c", script], environment: environment, timeout: timeout)
    }

    @Test func capturesStatusStdoutAndStderr() throws {
        let output = try sh("printf out; printf err >&2; exit 3")
        #expect(output.status == 3)
        #expect(output.exited)
        #expect(String(decoding: output.stdout, as: UTF8.self) == "out")
        #expect(String(decoding: output.stderr, as: UTF8.self) == "err")
    }

    @Test func largeStderrDoesntBlockStdout() throws {
        let output = try sh("head -c 200000 /dev/zero | tr '\\\\0' e >&2; printf done", timeout: 10)
        #expect(String(decoding: output.stdout, as: UTF8.self) == "done")
        #expect(output.stderr.count == 200_000)
    }

    @Test func usesTheGivenEnvironment() throws {
        let output = try sh(#"printf '%s' "$ATOLL_X""#, environment: ["ATOLL_X": "1"])
        #expect(String(decoding: output.stdout, as: UTF8.self) == "1")
    }

    @Test func aBackgroundChildHoldingStdoutDoesntBlock() throws {
        let start = Date()
        let output = try sh("sleep 30 & printf ok", timeout: 10)
        #expect(String(decoding: output.stdout, as: UTF8.self) == "ok")
        #expect(Date().timeIntervalSince(start) < 10)
    }

    @Test func aProgramThatOutlivesTheTimeoutIsStopped() throws {
        let pidFile = FileManager.default.temporaryDirectory.appendingPathComponent("atoll-pid-\(UUID().uuidString)").path
        let start = Date()
        #expect(throws: ProcessRunner.Failure.timedOut) { try sh("echo $$ > \(pidFile); sleep 30", timeout: 0.5) }
        #expect(Date().timeIntervalSince(start) < 10)
        #expect(!isRunning(try pid(in: pidFile)))
    }

    @Test func aProgramIgnoringSIGTERMIsKilled() throws {
        let pidFile = FileManager.default.temporaryDirectory.appendingPathComponent("atoll-pid-\(UUID().uuidString)").path
        let start = Date()
        #expect(throws: ProcessRunner.Failure.timedOut) {
            try sh("echo $$ > \(pidFile); trap '' TERM; while :; do sleep 0.1; done", timeout: 0.5)
        }
        #expect(Date().timeIntervalSince(start) < 10)
        #expect(!isRunning(try pid(in: pidFile)))
    }

    func pid(in file: String) throws -> pid_t {
        pid_t(try String(contentsOfFile: file, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    /// Alive and not a zombie waiting to be reaped.
    func isRunning(_ pid: pid_t) -> Bool {
        guard pid > 0, kill(pid, 0) == 0 else { return false }
        var info = proc_bsdinfo()
        let size = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
        return size > 0 && info.pbi_status != UInt32(SZOMB)
    }

    @Test func aSignalIsNotAnExit() throws {
        let output = try sh("kill -9 $$")
        #expect(!output.exited)
    }

    @Test func aProgramThatCantStartThrowsTheSystemError() {
        #expect {
            try ProcessRunner.run("/nonexistent/tool", [])
        } throws: { error in
            !(error is ProcessRunner.Failure) && "\(error)".contains("Error Domain=")
        }
    }

    @Test func asyncVariant() async throws {
        let output = try await ProcessRunner.run("/bin/sh", ["-c", "printf hi"], timeout: 5)
        #expect(String(decoding: output.stdout, as: UTF8.self) == "hi")
    }
}
