import Foundation

// Wire-level types mirrored from herdr-core (protocol generation 1).
// Decoding is deliberately tolerant: the protocol is preview and only grows,
// so every non-essential field is optional and unknown fields are ignored.

public struct CoreStatus: Decodable, Equatable, Sendable {
    public var state: String
    public var app: String?
    public var kind: String?
    public var msg: String?
    public var title: String?
    public var progress: Int?

    public init(state: String, app: String? = nil, kind: String? = nil, msg: String? = nil, title: String? = nil, progress: Int? = nil) {
        self.state = state
        self.app = app
        self.kind = kind
        self.msg = msg
        self.title = title
        self.progress = progress
    }
}

public struct CoreForeground: Decodable, Equatable, Sendable {
    public var pid: Int?
    public var name: String?
    public var argv: [String]?
    public var cwd: String?

    public init(pid: Int? = nil, name: String? = nil, argv: [String]? = nil, cwd: String? = nil) {
        self.pid = pid
        self.name = name
        self.argv = argv
        self.cwd = cwd
    }
}

public struct TerminalInfo: Decodable, Equatable, Sendable {
    public var address: String
    public var name: String?
    public var argv: [String]
    public var cwd: String
    /// "live" or "finished".
    public var state: String
    public var createdMs: UInt64?
    public var finishedMs: UInt64?
    public var status: CoreStatus?
    public var statusMs: UInt64?
    public var reported: Bool
    public var turn: UInt64
    public var title: String
    public var foreground: CoreForeground?
    public var labels: [String: String]
    public var template: String?
    public var exitCode: Int?
    public var reason: String?

    public init(
        address: String, name: String? = nil, argv: [String] = [], cwd: String = "/",
        state: String = "live", createdMs: UInt64? = nil, finishedMs: UInt64? = nil,
        status: CoreStatus? = nil, statusMs: UInt64? = nil, reported: Bool = false,
        turn: UInt64 = 0, title: String = "", foreground: CoreForeground? = nil,
        labels: [String: String] = [:], template: String? = nil, exitCode: Int? = nil, reason: String? = nil
    ) {
        self.address = address
        self.name = name
        self.argv = argv
        self.cwd = cwd
        self.state = state
        self.createdMs = createdMs
        self.finishedMs = finishedMs
        self.status = status
        self.statusMs = statusMs
        self.reported = reported || status != nil
        self.turn = turn
        self.title = title
        self.foreground = foreground
        self.labels = labels
        self.template = template
        self.exitCode = exitCode
        self.reason = reason
    }

    enum CodingKeys: String, CodingKey {
        case address, name, argv, cwd, state, status, reported, turn, title, foreground, labels, template, reason
        case createdMs = "created_ms"
        case finishedMs = "finished_ms"
        case statusMs = "status_ms"
        case exitCode = "exit_code"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        address = try c.decode(String.self, forKey: .address)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        argv = (try? c.decodeIfPresent([String].self, forKey: .argv)) ?? []
        cwd = (try? c.decodeIfPresent(String.self, forKey: .cwd)) ?? "/"
        state = (try? c.decodeIfPresent(String.self, forKey: .state)) ?? "live"
        createdMs = try? c.decodeIfPresent(UInt64.self, forKey: .createdMs)
        finishedMs = try? c.decodeIfPresent(UInt64.self, forKey: .finishedMs)
        status = try? c.decodeIfPresent(CoreStatus.self, forKey: .status)
        statusMs = try? c.decodeIfPresent(UInt64.self, forKey: .statusMs)
        reported = (try? c.decodeIfPresent(Bool.self, forKey: .reported)) ?? (status != nil)
        turn = (try? c.decodeIfPresent(UInt64.self, forKey: .turn)) ?? 0
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        foreground = try? c.decodeIfPresent(CoreForeground.self, forKey: .foreground)
        labels = (try? c.decodeIfPresent([String: String].self, forKey: .labels)) ?? [:]
        template = try? c.decodeIfPresent(String.self, forKey: .template)
        exitCode = try? c.decodeIfPresent(Int.self, forKey: .exitCode)
        reason = try? c.decodeIfPresent(String.self, forKey: .reason)
    }
}

/// One fact change from `events.subscribe`.
public enum CoreEvent: Equatable, Sendable {
    case created(TerminalInfo)
    case status(terminal: String, status: CoreStatus?, reported: Bool)
    case turn(terminal: String, turn: UInt64, state: String?)
    case title(terminal: String, title: String)
    case labels(terminal: String, labels: [String: String])
    case foreground(terminal: String, foreground: CoreForeground?)
    case finished(terminal: String, exitCode: Int?, reason: String?, finishedMs: UInt64?)
    case removed(terminal: String)
    case lost(terminal: String)
    case restarted(terminal: String)
    /// Any event type this client doesn't act on (keep, size, doc, future types).
    case other(terminal: String?, type: String)

    public var terminal: String? {
        switch self {
        case .created(let t): t.address
        case .status(let t, _, _), .turn(let t, _, _), .title(let t, _), .labels(let t, _),
             .foreground(let t, _), .finished(let t, _, _, _), .removed(let t), .lost(let t), .restarted(let t):
            t
        case .other(let t, _): t
        }
    }
}

public struct CoreHello: Equatable, Sendable {
    public var generation: Int
    public var version: String
    public var methods: [String]

    public init(generation: Int, version: String, methods: [String]) {
        self.generation = generation
        self.version = version
        self.methods = methods
    }
}

/// What the HerdrClient reports about the core connection and its event stream.
public enum ClientUpdate: Equatable, Sendable {
    case connecting
    case connected(CoreHello)
    case snapshot(seq: UInt64, terminals: [TerminalInfo])
    case event(seq: UInt64, CoreEvent)
    case heartbeat(seq: UInt64)
    /// The subscriber fell behind; a fresh snapshot follows.
    case missed
    case disconnected(reason: String)
    /// The core refused this client's protocol (e.g. `unsupported_generation`).
    case incompatible(reason: String)
}

/// herdr-core's structured error: `{kind, message, hint}`.
public struct HerdrError: Error, Equatable, Sendable {
    public var kind: String
    public var message: String
    public var hint: String?

    public init(kind: String, message: String, hint: String? = nil) {
        self.kind = kind
        self.message = message
        self.hint = hint
    }

    public static func unavailable(_ message: String) -> HerdrError {
        HerdrError(kind: "unavailable", message: message)
    }
}

public struct ReadOutput: Equatable, Sendable {
    public var text: String
    /// "screen", "history" or "stitched".
    public var how: String
    public var complete: Bool
    /// Why only the screen: "working", "blocked" or "error".
    public var why: String?

    public init(text: String, how: String, complete: Bool = true, why: String? = nil) {
        self.text = text
        self.how = how
        self.complete = complete
        self.why = why
    }

    public var isScreenOnly: Bool { how == "screen" }
}

public struct SendOutput: Equatable, Sendable {
    /// true: went working; false: didn't; nil: doesn't report status, nobody can tell.
    public var started: Bool?
    public var turn: UInt64

    public init(started: Bool?, turn: UInt64 = 0) {
        self.started = started
        self.turn = turn
    }
}

public enum InterruptOutcome: String, Equatable, Sendable {
    case stopped, exited, stillWorking = "still_working", unknown

    public var label: String {
        switch self {
        case .stopped: "stopped"
        case .exited: "exited"
        case .stillWorking: "still working"
        case .unknown: "unknown"
        }
    }
}

public struct TemplateInfo: Equatable, Sendable, Decodable {
    public var name: String
    public var description: String
    public var command: String
    public var error: String?

    public init(name: String, description: String = "", command: String = "", error: String? = nil) {
        self.name = name
        self.description = description
        self.command = command
        self.error = error
    }
}

public struct LaunchRequest: Equatable, Sendable {
    public var argv: [String]
    public var folder: String
    public var task: String
    public var name: String?
    /// The space to start in (nil / empty: Herdr's selected one). Without the app, a new space's id.
    public var space: String?
    /// `argv[0]` names a herdr-core template (core sends the task itself).
    public var template: Bool
    /// Start in a new space with this name (empty: Herdr names it after the folder).
    public var newSpaceName: String?
    /// The Herdr app isn't running: start it in herdr-core, labelled for the space it should show in.
    public var withoutApp: Bool

    public init(
        argv: [String], folder: String, task: String, name: String? = nil, space: String? = nil,
        template: Bool = false, newSpaceName: String? = nil, withoutApp: Bool = false
    ) {
        self.argv = argv
        self.folder = folder
        self.task = task
        self.name = name
        self.space = space
        self.template = template
        self.newSpaceName = newSpaceName
        self.withoutApp = withoutApp
    }
}

/// What the launch form's Space picker holds.
public enum LaunchSpaceChoice: Hashable, Sendable {
    /// Herdr's selected space (without the app: the one it showed last).
    case selected
    case existing(String)
    /// A new space (its name travels separately: `LaunchRequest.newSpaceName`).
    case new

    /// Stored form (Settings' default, recipes): "" = selected, else a space id.
    public init(stored: String) {
        self = stored.isEmpty ? .selected : .existing(stored)
    }

    /// A new space isn't stored: recipes and defaults name existing spaces only.
    public var stored: String {
        if case .existing(let id) = self { id } else { "" }
    }
}

extension LaunchRequest {
    /// A request from the launch form's choices: the space picker and the tool's option id (`template:` ones are
    /// herdr-core templates). `newSpaceName` only counts for `.new`.
    public init(argv: [String], folder: String, task: String, name: String?, optionID: String,
                space choice: LaunchSpaceChoice, newSpaceName: String) {
        self.init(argv: argv, folder: folder, task: task, name: name,
                  template: LaunchHistory.templateName(of: optionID) != nil)
        switch choice {
        case .selected: break
        case .existing(let id): space = id
        case .new: self.newSpaceName = newSpaceName.trimmingCharacters(in: .whitespaces)
        }
    }
}

public struct LaunchOutput: Equatable, Sendable {
    /// The terminal Herdr created, when it says.
    public var terminal: String?

    public init(terminal: String?) {
        self.terminal = terminal
    }
}

public struct HerdrSpace: Equatable, Sendable, Identifiable, Codable {
    public var id: String
    public var name: String
    /// Terminal addresses with a pane (or shown as a sub-agent) in this space.
    public var terminals: [String]
    /// The space the Herdr window shows.
    public var active: Bool

    public init(id: String, name: String, terminals: [String] = [], active: Bool = false) {
        self.id = id
        self.name = name
        self.terminals = terminals
        self.active = active
    }
}
