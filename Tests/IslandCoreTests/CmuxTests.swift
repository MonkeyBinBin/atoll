import Darwin
import Foundation
import Testing
@testable import IslandCore

/// Frames shaped like cmux's `events` stream (protocol cmux-events v1).
@Suite("cmux")
struct CmuxTests {
    let surface = "D38AC370-844A-491D-A008-B175DB0DF049"
    let workspace = "B91DA891-6D36-4968-8837-2854D1394476"

    func hook(_ name: String, session: String = "S1", boot: String = "BOOT", cwd: String = "/Users/me/dotfiles", pid: Int = 44475, source: String = "claude", seq: Int = 1) -> [String: Any] {
        [
            "type": "event", "boot_id": boot, "category": "agent", "name": "agent.hook.\(name)", "seq": seq,
            "source": source, "surface_id": surface, "workspace_id": workspace,
            "payload": [
                "_source": source, "_ppid": pid, "cwd": cwd, "hook_event_name": name, "phase": "received",
                "session_id": "cmux-feed-v1:\(session)", "surface_id": surface, "workspace_id": workspace,
            ] as [String: Any],
        ]
    }

    func sidebar(_ value: String, boot: String = "BOOT") -> [String: Any] {
        [
            "type": "event", "boot_id": boot, "category": "sidebar", "name": "sidebar.metadata.updated", "seq": 9,
            "payload": ["command": "set_status", "args": "claude_code \(value) --icon=hourglass --color=#8E8E93 --tab=\(workspace)"],
        ]
    }

    /// Sessions in these tests use distinct pids unless they share a process on purpose.
    func status(_ s: CmuxSessions, pid: Int = 44475) -> String? {
        s.terminals().first { $0.address == "cmux:pid\(pid)" }?.status?.state
    }

    @Test("hooks drive the session's status")
    func lifecycle() {
        var s = CmuxSessions()
        s.apply(hook("SessionStart"))
        #expect(status(s) == "idle")
        s.apply(hook("UserPromptSubmit"))
        #expect(status(s) == "working")
        s.apply(hook("PreToolUse"))
        #expect(status(s) == "working")
        s.apply(hook("Stop"))
        #expect(status(s) == "done")
        s.apply(hook("SessionEnd"))
        #expect(s.terminals().isEmpty)
    }

    @Test("terminals carry app, cwd, pid and the surface for commands")
    func terminalShape() throws {
        var s = CmuxSessions()
        s.apply(hook("UserPromptSubmit"))
        let t = try #require(s.terminals().first)
        #expect(t.address == "cmux:pid44475")
        #expect(t.status?.app == "claude-code")
        #expect(t.cwd == "/Users/me/dotfiles")
        #expect(t.foreground?.pid == 44475)
        #expect(t.labels["island.cmux.surface"] == surface)
    }

    @Test("the last hook's occurred_at becomes the status time")
    func statusTime() throws {
        var s = CmuxSessions()
        var frame = hook("Stop")
        frame["occurred_at"] = "2026-11-04T06:49:41.616Z"
        s.apply(frame)
        let t = try #require(s.terminals().first)
        #expect(t.statusMs == 1_793_774_981_616)
    }

    @Test("sub-agent hooks don't mark the main agent done")
    func subagents() {
        var s = CmuxSessions()
        s.apply(hook("PreToolUse"))
        s.apply(hook("SubagentStop"))
        #expect(status(s) == "working")
    }

    @Test("PermissionRequest → Needs you · Permission, and the Notification after it keeps that")
    func permission() throws {
        var s = CmuxSessions()
        s.apply(hook("PreToolUse"))
        s.apply(hook("PermissionRequest"))
        s.apply(hook("Notification"))
        let t = try #require(s.terminals().first)
        #expect(t.status?.state == "blocked")
        #expect(t.status?.kind == "permission")
        s.apply(hook("PostToolUse"))
        #expect(status(s) == "working")
    }

    @Test("AskUserQuestion → Needs you · Question")
    func question() throws {
        var s = CmuxSessions()
        var frame = hook("PreToolUse")
        var payload = frame["payload"] as! [String: Any]
        payload["tool_name"] = "AskUserQuestion"
        frame["payload"] = payload
        s.apply(frame)
        let t = try #require(s.terminals().first)
        #expect(t.status?.state == "blocked")
        #expect(t.status?.kind == "question")
    }

    @Test("an idle-reminder Notification keeps the previous state (an unseen Done stays Done)")
    func idleReminder() {
        var s = CmuxSessions()
        s.apply(hook("Stop"))
        s.apply(hook("Notification"))
        #expect(status(s) == "done")
        // The workspace sidebar is shared across sessions, so it never decides one session's state.
        s.apply(sidebar("Needs input"))
        #expect(status(s) == "done")
    }

    @Test("sessions sharing a surface stay separate (keyed by session_id)")
    func sharedSurface() {
        var s = CmuxSessions()
        s.apply(hook("UserPromptSubmit", session: "real", pid: 44475))
        s.apply(hook("Stop", session: "inherited", cwd: "/Users/me/other", pid: 61064))
        #expect(s.terminals().count == 2)
        #expect(status(s, pid: 44475) == "working")
        #expect(status(s, pid: 61064) == "done")
        // The adapter drops sessions owned by herdr through `include`.
        #expect(s.terminals { $0.pid != 61064 }.map(\.address) == ["cmux:pid44475"])
    }

    @Test("/clear (new session, same process) keeps the same agent")
    func clearKeepsIdentity() {
        var s = CmuxSessions()
        s.apply(hook("Stop", session: "before"))
        s.apply(hook("SessionEnd", session: "before"))
        s.apply(hook("SessionStart", session: "after"))
        #expect(s.terminals().map(\.address) == ["cmux:pid44475"])
        #expect(status(s) == "idle")
    }

    @Test("history from an earlier cmux boot is dropped")
    func bootReset() {
        var s = CmuxSessions()
        s.apply(hook("UserPromptSubmit", session: "old", boot: "A", pid: 1))
        s.apply(hook("SessionStart", session: "new", boot: "B", pid: 2))
        #expect(s.terminals().map(\.address) == ["cmux:pid2"])
    }

    @Test("feed and other frames are ignored")
    func ignoresOthers() {
        var s = CmuxSessions()
        s.apply(["type": "event", "boot_id": "BOOT", "name": "feed.item.received", "payload": ["session_id": "x", "surface_id": surface, "hook_event_name": "Stop"]])
        s.apply(["type": "ack", "boot_id": "BOOT"])
        #expect(s.terminals().isEmpty)
    }

    @Test("CLI errors parse into kind and message")
    func errors() {
        #expect(CmuxAdapter.parseError("Error: invalid_params: Unknown key\n") == HerdrError(kind: "invalid_params", message: "Unknown key"))
        #expect(CmuxAdapter.parseError("Error: not_found: Workspace not found") == HerdrError(kind: "not_found", message: "Workspace not found"))
        #expect(CmuxAdapter.parseError("boom").kind == "cmux")
    }

    @Test("named keys use send-key; digits and letters are typed")
    func keys() {
        #expect(CmuxAdapter.keyCommand(surface: "S", key: "enter") == ["send-key", "--surface", "S", "--force", "enter"])
        #expect(CmuxAdapter.keyCommand(surface: "S", key: "esc") == ["send-key", "--surface", "S", "--force", "esc"])
        #expect(CmuxAdapter.keyCommand(surface: "S", key: "1") == ["send", "--surface", "S", "--force", "--", "1"])
    }

    @Test("process environment can be read for this user's processes")
    func processEnvironment() {
        let env = ProcessInspector.environment(of: getpid())
        #expect(env?["PATH"] != nil)
        #expect(ProcessInspector.isAlive(getpid()))
        #expect(!ProcessInspector.isAlive(999_999))
    }
}
