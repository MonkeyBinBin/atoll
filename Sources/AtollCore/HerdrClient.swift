import Foundation

/// Everything the app needs from Herdr. Returns Herdr's structured results and
/// `HerdrError`s; makes no UI decisions.
///
/// Updates are delivered on the main actor, in order, to the handler passed to `start`.
public protocol HerdrClient: AnyObject, Sendable {
    /// Connect and subscribe; keep reconnecting until `stop`.
    @MainActor func start(onUpdate: @escaping @MainActor (ClientUpdate) -> Void)
    /// Drop the current connection and subscribe again now.
    @MainActor func reconnect()
    @MainActor func stop()

    func read(terminal: String, lines: Int) async throws -> ReadOutput
    func send(terminal: String, text: String, force: Bool) async throws -> SendOutput
    func keys(terminal: String, keys: [String]) async throws
    func interrupt(terminal: String) async throws -> InterruptOutcome
    func templates() async throws -> [TemplateInfo]

    // Herdr GUI (herdr-app) commands.
    func isHerdrAppRunning() async -> Bool
    func spaces() async throws -> [HerdrSpace]
    func launch(_ request: LaunchRequest) async throws -> LaunchOutput
    func focus(terminal: String) async throws
    func renameSpace(id: String, name: String) async throws
}

extension HerdrClient {
    public func renameSpace(id: String, name: String) async throws {
        throw HerdrError(kind: "unsupported", message: "Renaming spaces goes through the Herdr app")
    }
}

/// A cancellable scheduled action.
@MainActor
public final class ScheduledAction {
    private var cancelled = false
    private let onCancel: () -> Void

    public init(onCancel: @escaping () -> Void = {}) {
        self.onCancel = onCancel
    }

    public var isCancelled: Bool { cancelled }

    public func cancel() {
        guard !cancelled else { return }
        cancelled = true
        onCancel()
    }
}

/// Time source and timer, injectable so timeouts are testable without sleeping.
@MainActor
public protocol IslandScheduler: AnyObject {
    var now: Date { get }
    @discardableResult
    func schedule(after seconds: TimeInterval, _ action: @escaping @MainActor () -> Void) -> ScheduledAction
}

@MainActor
public final class LiveScheduler: IslandScheduler {
    public init() {}

    public var now: Date { Date() }

    @discardableResult
    public func schedule(after seconds: TimeInterval, _ action: @escaping @MainActor () -> Void) -> ScheduledAction {
        let handle = ScheduledAction()
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            MainActor.assumeIsolated {
                if !handle.isCancelled { action() }
            }
        }
        return handle
    }
}
