import Foundation
import Testing
@testable import AtollCore

/// Pins how the herdr-app/hc and cmux runners turn a program's exit and output into results and errors, using
/// small scripts in place of the real tools. Spawns processes, so it's opt-in:
///   ATOLL_PROCESS_TESTS=1 swift test --filter ProcessCallers
@Suite("Process callers (real processes)",
       .enabled(if: ProcessInfo.processInfo.environment["ATOLL_PROCESS_TESTS"] == "1"))
struct ProcessCallersTests {
    /// An executable `sh` script with this body, in a fresh temporary directory.
    func script(_ body: String) throws -> String {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("atoll-script-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("tool").path
        try "#!/bin/sh\n\(body)\n".write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        return path
    }

    func herdrError(_ path: String) async -> HerdrError? {
        do {
            _ = try await CoreRPCAdapter.run(path, [], tool: "hc")
            return nil
        } catch {
            return error as? HerdrError
        }
    }

    // MARK: herdr-app / hc

    @Test func herdrAppReturnsStdoutOnSuccess() async throws {
        let data = try await CoreRPCAdapter.run(try script(#"printf '{"ok":true}'; echo noise >&2"#), [], tool: "hc")
        #expect(String(decoding: data, as: UTF8.self) == #"{"ok":true}"#)
    }

    @Test func herdrAppPassesArguments() async throws {
        let data = try await CoreRPCAdapter.run(try script(#"printf '%s|' "$@""#), ["a b", "c"], tool: "hc")
        #expect(String(decoding: data, as: UTF8.self) == "a b|c|")
    }

    @Test func herdrAppJSONErrorWinsEvenOnExitZero() async throws {
        let error = await herdrError(try script(#"printf '{"error":{"kind":"not_found","message":"gone","hint":"h"}}'"#))
        #expect(error == HerdrError(kind: "not_found", message: "gone", hint: "h"))
    }

    @Test func herdrAppJSONErrorOnStderr() async throws {
        let error = await herdrError(try script(#"printf '{"error":{"kind":"busy","message":"later"}}' >&2; exit 3"#))
        #expect(error == HerdrError(kind: "busy", message: "later"))
    }

    @Test func herdrAppNonzeroExitUsesStderrThenStdout() async throws {
        #expect(await herdrError(try script("echo '  bad thing  ' >&2; echo out; exit 2"))
            == HerdrError(kind: "app_command_failed", message: "bad thing"))
        #expect(await herdrError(try script("echo only-out; exit 2"))
            == HerdrError(kind: "app_command_failed", message: "only-out"))
        #expect(await herdrError(try script("exit 4"))
            == HerdrError(kind: "app_command_failed", message: "hc exited with 4"))
    }

    @Test func herdrAppThatCantStart() async {
        let error = await herdrError("/nonexistent/hc")
        #expect(error?.kind == "app_command_failed")
        #expect(error?.message.hasPrefix("Error Domain=NSCocoaErrorDomain") == true)
    }

    @Test func herdrAppBackgroundChildHoldingOutputDoesntBlock() async throws {
        let start = Date()
        let data = try await CoreRPCAdapter.run(try script("sleep 30 & printf done"), [], tool: "hc")
        #expect(String(decoding: data, as: UTF8.self) == "done")
        #expect(Date().timeIntervalSince(start) < 10)
    }

    // MARK: cmux

    @Test func cmuxReturnsStdoutAndSetsQuiet() throws {
        let data = try CmuxAdapter.run(try script(#"printf '%s:%s' "$CMUX_QUIET" "$1""#), ["x"])
        #expect(String(decoding: data, as: UTF8.self) == "1:x")
    }

    @Test func cmuxNonzeroExitParsesStderrThenStdout() throws {
        #expect(throws: HerdrError(kind: "not_found", message: "Workspace not found")) {
            try CmuxAdapter.run(try script("echo 'Error: not_found: Workspace not found' >&2; exit 1"), [])
        }
        #expect(throws: HerdrError(kind: "cmux", message: "boom")) {
            try CmuxAdapter.run(try script("echo 'Error: boom'; exit 1"), [])
        }
    }

    @Test func cmuxThatCantStartThrows() {
        #expect(throws: (any Error).self) { try CmuxAdapter.run("/nonexistent/cmux", []) }
    }
}
