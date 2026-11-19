import Darwin
import Foundation
import Testing
@testable import AtollCore

/// Frames shaped like cmux's `events` stream (protocol cmux-events v1).
@Suite("cmux")
struct CmuxTests {
    let surface = "D38AC370-844A-491D-A008-B175DB0DF049"
    let workspace = "B91DA891-6D36-4968-8837-2854D1394476"

    func hook(_ name: String, session: String = "S1", boot: String = "BOOT", cwd: String = "/Users/me/dotfiles", pid: Int? = 44475, source: String = "claude", seq: Int = 1) -> [String: Any] {
        var payload: [String: Any] = [
            "_source": source, "cwd": cwd, "hook_event_name": name, "phase": "received",
            "session_id": "cmux-feed-v1:\(session)", "surface_id": surface, "workspace_id": workspace,
        ]
        payload["_ppid"] = pid
        return [
            "type": "event", "boot_id": boot, "category": "agent", "name": "agent.hook.\(name)", "seq": seq,
            "source": source, "surface_id": surface, "workspace_id": workspace,
            "payload": payload,
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
    }

    @Test("/exit: the agent stays through the grace period, then goes")
    func exitAfterGrace() {
        var s = CmuxSessions()
        s.apply(at(hook("Stop"), "10.000"), now: date("10.000"))
        s.apply(at(hook("SessionEnd"), "15.600"), now: date("15.600"))
        #expect(s.terminals(now: date("17.500")).map(\.address) == ["cmux:pid44475"])
        #expect(s.terminals(now: date("17.700")).isEmpty)
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
        #expect(t.labels["atoll.cmux.surface"] == surface)
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

    @Test("cmux's own AskUserQuestion hook and the Notification after it keep the question open")
    func questionAsCmuxSendsIt() throws {
        // Recorded from cmux: PreToolUse(AskUserQuestion) → agent.hook.AskUserQuestion → Notification.
        var s = CmuxSessions()
        s.apply(hook("UserPromptSubmit"))
        for name in ["PreToolUse", "AskUserQuestion"] {
            var frame = hook(name)
            var payload = frame["payload"] as! [String: Any]
            payload["tool_name"] = "AskUserQuestion"
            frame["payload"] = payload
            s.apply(frame)
        }
        s.apply(hook("Notification"))
        let t = try #require(s.terminals().first)
        #expect(t.status?.state == "blocked")
        #expect(t.status?.kind == "question")
        s.apply(hook("PostToolUse"))
        #expect(status(s) == "working")
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

    func at(_ frame: [String: Any], _ time: String) -> [String: Any] {
        var frame = frame
        frame["occurred_at"] = "2026-11-18T10:01:\(time)Z"
        return frame
    }

    func date(_ time: String) -> Date { CmuxSessions.parseDate("2026-11-18T10:01:\(time)Z")! }

    @Test("/clear: the agent stays between the old SessionEnd and the new SessionStart")
    func clearGap() {
        // Recorded from cmux (pid 41108): SessionStart of the new session came 109 ms after the old SessionEnd.
        var s = CmuxSessions()
        s.apply(at(hook("Stop", session: "before"), "10.000"), now: date("10.000"))
        s.apply(at(hook("SessionEnd", session: "before"), "15.600"), now: date("15.600"))
        #expect(s.terminals(now: date("15.650")).map(\.address) == ["cmux:pid44475"])
        #expect(s.terminals(now: date("15.650")).first?.status?.state == "done")
        s.apply(at(hook("SessionStart", session: "after"), "15.709"), now: date("15.709"))
        let after = s.terminals(now: date("15.750"))
        #expect(after.map(\.address) == ["cmux:pid44475"])
        #expect(after.first?.labels[SessionHint.idLabel] == "cmux-feed-v1:after")
        #expect(after.first?.status?.state == "idle")
    }

    @Test("/clear with cmux's duplicate frames: a late repeat of the old SessionEnd doesn't win or restart the grace")
    func clearDuplicates() {
        // cmux sends every hook twice; the repeat of the old SessionEnd may land after the new SessionStart.
        var s = CmuxSessions()
        s.apply(at(hook("Stop", session: "before"), "10.000"), now: date("10.000"))
        s.apply(at(hook("SessionEnd", session: "before"), "15.600"), now: date("15.600"))
        s.apply(at(hook("SessionStart", session: "after"), "15.709"), now: date("15.709"))
        s.apply(at(hook("SessionEnd", session: "before"), "15.710"), now: date("15.710"))
        s.apply(at(hook("SessionStart", session: "after"), "15.711"), now: date("15.711"))
        #expect(s.terminals(now: date("15.750")).first?.labels[SessionHint.idLabel] == "cmux-feed-v1:after")
        // The grace counts from the first SessionEnd.
        var exit = CmuxSessions()
        exit.apply(at(hook("Stop"), "10.000"), now: date("10.000"))
        exit.apply(at(hook("SessionEnd"), "15.600"), now: date("15.600"))
        exit.apply(at(hook("SessionEnd"), "17.000"), now: date("17.000"))
        #expect(exit.terminals(now: date("17.700")).isEmpty)
    }

    @Test("a late repeat of the old session's hooks doesn't bring it back")
    func endedStaysEnded() {
        var s = CmuxSessions()
        s.apply(at(hook("Stop", session: "before"), "10.000"), now: date("10.000"))
        s.apply(at(hook("SessionEnd", session: "before"), "15.600"), now: date("15.600"))
        s.apply(at(hook("SessionStart", session: "after"), "15.709"), now: date("15.709"))
        s.apply(at(hook("Stop", session: "before"), "15.710"), now: date("15.710"))
        let t = s.terminals(now: date("15.750"))
        #expect(t.first?.labels[SessionHint.idLabel] == "cmux-feed-v1:after")
        #expect(t.first?.status?.state == "idle")
        // Ending without a new session: the repeat doesn't restart it either.
        var exit = CmuxSessions()
        exit.apply(at(hook("Stop"), "10.000"), now: date("10.000"))
        exit.apply(at(hook("SessionEnd"), "15.600"), now: date("15.600"))
        exit.apply(at(hook("Stop"), "15.610"), now: date("15.610"))
        #expect(exit.terminals(now: date("17.700")).isEmpty)
    }

    @Test("replayed history: a repeat of an ended session's hook doesn't revive it after it was forgotten")
    func endedStaysEndedAfterPrune() {
        // Replay applies old frames at the current time, so every ended session is already past its grace.
        var s = CmuxSessions()
        s.apply(at(hook("Stop", session: "before"), "10.000"))
        s.apply(at(hook("SessionEnd", session: "before"), "15.600"))
        s.apply(at(hook("SessionStart", session: "after"), "15.709"))
        s.apply(at(hook("Stop", session: "before"), "15.710"))
        #expect(s.terminals(now: date("15.750")).first?.labels[SessionHint.idLabel] == "cmux-feed-v1:after")
        // `/resume` of that session still works.
        s.apply(at(hook("SessionStart", session: "before"), "20.000"))
        #expect(s.sessions["cmux-feed-v1:before"]?.ended == false)
    }

    @Test("ended sessions are forgotten once their grace is over")
    func pruneEnded() {
        var s = CmuxSessions()
        s.apply(at(hook("Stop", session: "before"), "10.000"), now: date("10.000"))
        s.apply(at(hook("SessionEnd", session: "before"), "15.600"), now: date("15.600"))
        s.apply(at(hook("SessionStart", session: "after"), "15.709"), now: date("15.709"))
        #expect(s.sessions["cmux-feed-v1:before"] != nil)
        s.apply(at(hook("UserPromptSubmit", session: "after"), "20.000"), now: date("20.000"))
        #expect(s.sessions["cmux-feed-v1:before"] == nil)
        // A SessionEnd for a session it never saw (e.g. a repeat after pruning) adds nothing.
        s.apply(at(hook("SessionEnd", session: "before"), "20.100"), now: date("20.100"))
        #expect(s.sessions["cmux-feed-v1:before"] == nil)
    }

    @Test("graceDeadline: when the earliest ending agent should be dropped")
    func graceDeadline() {
        var s = CmuxSessions()
        s.apply(at(hook("Stop"), "10.000"), now: date("10.000"))
        #expect(s.graceDeadline(now: date("10.100")) == nil)
        s.apply(at(hook("SessionEnd"), "15.600"), now: date("15.600"))
        #expect(s.graceDeadline(now: date("15.650")) == date("17.600"))
        #expect(s.graceDeadline(now: date("17.700")) == nil)
    }

    @Test("without a pid an ended session goes at once (the next session is another agent anyway)")
    func noPidNoGrace() {
        var s = CmuxSessions()
        s.apply(at(hook("Stop", session: "before", pid: nil), "10.000"), now: date("10.000"))
        s.apply(at(hook("SessionEnd", session: "before", pid: nil), "15.600"), now: date("15.600"))
        #expect(s.terminals(now: date("15.650")).isEmpty)
    }

    @Test("a session that lost its SessionEnd doesn't take the agent over while a newer one is ending")
    func staleLiveLosesToNewerEnding() {
        // A's SessionEnd never came, so A still looks live; B, newer, is ending through `/clear`.
        var s = CmuxSessions()
        s.apply(at(hook("UserPromptSubmit", session: "A"), "01.000"), now: date("01.000"))
        s.apply(at(hook("SessionStart", session: "B"), "02.000"), now: date("02.000"))
        s.apply(at(hook("Stop", session: "B"), "03.000"), now: date("03.000"))
        s.apply(at(hook("SessionEnd", session: "B"), "04.000"), now: date("04.000"))
        let t = s.terminals(now: date("04.050"))
        #expect(t.first?.labels[SessionHint.idLabel] == "cmux-feed-v1:B")
        #expect(t.first?.status?.state == "done")
        // The next session takes over at once.
        s.apply(at(hook("SessionStart", session: "C"), "04.100"), now: date("04.100"))
        #expect(s.terminals(now: date("04.150")).first?.labels[SessionHint.idLabel] == "cmux-feed-v1:C")
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
