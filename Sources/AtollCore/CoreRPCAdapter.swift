import Foundation

/// HerdrClient over herdr-core's Unix socket (JSON-RPC 2.0, one message per line),
/// plus `herdr-app do …` for the GUI-owned commands (launch, focus). Without the app, launches go through
/// `hc run`, labelled for the Herdr space they should show in (`HerdrLabels`).
///
/// The event subscription has its own connection (a subscribed plain connection only
/// carries notifications). Every command opens a short-lived connection of its own, so
/// slow calls (`terminal.send` waits for the user to stop typing) never block others.
public final class CoreRPCAdapter: HerdrClient, @unchecked Sendable {
    public let socketPath: String
    public let herdrAppPath: String?
    public let hcPath: String?
    private let appRunning: @Sendable () -> Bool
    private let activateApp: @Sendable () -> Void

    private let lock = NSLock()
    private var running = false
    private var generation = 0
    private var currentSocket: LineSocket?
    private var handler: (@MainActor (ClientUpdate) -> Void)?

    public init(
        socketPath: String = CoreRPCAdapter.defaultSocketPath(),
        herdrAppPath: String? = CoreRPCAdapter.findHerdrApp(),
        hcPath: String? = CoreRPCAdapter.findHC(),
        appRunning: @escaping @Sendable () -> Bool = { false },
        activateApp: @escaping @Sendable () -> Void = {}
    ) {
        self.socketPath = socketPath
        self.herdrAppPath = herdrAppPath
        self.hcPath = hcPath
        self.appRunning = appRunning
        self.activateApp = activateApp
    }

    public static func defaultSocketPath() -> String {
        let env = ProcessInfo.processInfo.environment
        if let explicit = env["HERDR_CORE_SOCKET"], !explicit.isEmpty { return explicit }
        let session = env["HC_SESSION"].flatMap { $0.isEmpty ? nil : $0 } ?? "default"
        let state = env["XDG_STATE_HOME"].flatMap { $0.isEmpty ? nil : $0 }
            ?? (NSHomeDirectory() as NSString).appendingPathComponent(".local/state")
        return (state as NSString).appendingPathComponent("herdr-core/\(session)/\(session).sock")
    }

    /// GUI apps don't inherit the shell PATH, so look in the usual install places.
    public static func findHerdrApp() -> String? {
        let home = NSHomeDirectory()
        let candidates = [
            "\(home)/.local/bin/herdr-app",
            "\(home)/Applications/Herdr.app/Contents/MacOS/Herdr",
            "/Applications/Herdr.app/Contents/MacOS/Herdr",
            "/opt/homebrew/bin/herdr-app",
            "/usr/local/bin/herdr-app",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// herdr-core's CLI, for launches while the Herdr app isn't running.
    public static func findHC() -> String? {
        let home = NSHomeDirectory()
        let candidates = ["\(home)/.local/bin/hc", "/opt/homebrew/bin/hc", "/usr/local/bin/hc"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    // MARK: Subscription

    @MainActor
    public func start(onUpdate: @escaping @MainActor (ClientUpdate) -> Void) {
        lock.lock()
        handler = onUpdate
        let alreadyRunning = running
        running = true
        lock.unlock()
        if !alreadyRunning { spawnLoop() }
    }

    @MainActor
    public func reconnect() {
        lock.lock()
        let socket = currentSocket
        lock.unlock()
        // Closing ends the blocking read; the loop reconnects at once.
        socket?.shutdown()
    }

    @MainActor
    public func stop() {
        lock.lock()
        running = false
        generation += 1
        let socket = currentSocket
        currentSocket = nil
        lock.unlock()
        socket?.shutdown()
    }

    private func spawnLoop() {
        lock.lock()
        generation += 1
        let gen = generation
        lock.unlock()
        let thread = Thread { [weak self] in self?.subscriptionLoop(generation: gen) }
        thread.name = "herdr-core events"
        thread.start()
    }

    private func isCurrent(_ gen: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return running && generation == gen
    }

    private func emit(_ update: ClientUpdate) {
        lock.lock()
        let handler = handler
        lock.unlock()
        guard let handler else { return }
        DispatchQueue.main.async {
            MainActor.assumeIsolated { handler(update) }
        }
    }

    private func subscriptionLoop(generation gen: Int) {
        var backoff: TimeInterval = 0.5
        while isCurrent(gen) {
            emit(.connecting)
            var reason = "connection closed"
            do {
                let socket = try LineSocket(path: socketPath)
                lock.lock()
                currentSocket = socket
                lock.unlock()
                defer {
                    socket.close()
                    lock.lock()
                    if currentSocket === socket { currentSocket = nil }
                    lock.unlock()
                }
                try socket.writeLine(Self.request(id: 1, method: "hello", params: ["generation": AgentStore.supportedGeneration]))
                let helloResult = try Self.result(of: try Self.readResponse(socket, id: 1))
                emit(.connected(Self.decodeHello(helloResult)))
                try socket.writeLine(Self.request(id: 2, method: "events.subscribe", params: [:]))
                var subscribed = false
                backoff = 0.5
                while isCurrent(gen), let line = socket.readLine() {
                    guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
                    if !subscribed, (object["id"] as? Int) == 2 {
                        let result = try Self.result(of: object)
                        let data = try JSONSerialization.data(withJSONObject: result)
                        let snapshot = try JSONDecoder().decode(SnapshotWire.self, from: data)
                        emit(.snapshot(seq: snapshot.seq, terminals: snapshot.terminals))
                        subscribed = true
                        continue
                    }
                    for update in Self.decodeNotification(object) {
                        emit(update)
                        if update == .missed, object["params"].flatMap({ ($0 as? [String: Any])?["terminals"] }) == nil {
                            // No snapshot attached: subscribe again to get one.
                            socket.shutdown()
                        }
                    }
                }
            } catch let error as HerdrError {
                if error.kind == "unsupported_generation" {
                    emit(.incompatible(reason: "herdr-core doesn't speak protocol generation \(AgentStore.supportedGeneration): \(error.message). Update the app or herdr-core."))
                    guard isCurrent(gen) else { return }
                    Thread.sleep(forTimeInterval: 30)
                    continue
                }
                reason = error.message
            } catch {
                reason = "\(error)"
            }
            guard isCurrent(gen) else { return }
            emit(.disconnected(reason: reason))
            Thread.sleep(forTimeInterval: backoff)
            backoff = min(backoff * 2, 5)
        }
    }

    // MARK: Wire decoding (internal, tested)

    struct SnapshotWire: Decodable {
        var seq: UInt64
        var terminals: [TerminalInfo]
    }

    static func decodeHello(_ result: Any) -> CoreHello {
        let dict = result as? [String: Any] ?? [:]
        return CoreHello(
            generation: (dict["generation"] as? Int) ?? 0,
            version: (dict["version"] as? String) ?? "?",
            methods: (dict["methods"] as? [String]) ?? []
        )
    }

    /// Notification → updates. Unknown methods and event types are tolerated.
    public static func decodeNotification(_ object: [String: Any]) -> [ClientUpdate] {
        guard let method = object["method"] as? String else { return [] }
        let params = object["params"] as? [String: Any] ?? [:]
        let seq = (params["seq"] as? NSNumber)?.uint64Value ?? 0
        switch method {
        case "heartbeat":
            return [.heartbeat(seq: seq)]
        case "missed", "snapshot":
            var updates: [ClientUpdate] = method == "missed" ? [.missed] : []
            if let terminals = params["terminals"],
               let data = try? JSONSerialization.data(withJSONObject: ["seq": seq, "terminals": terminals]),
               let snapshot = try? JSONDecoder().decode(SnapshotWire.self, from: data) {
                updates.append(.snapshot(seq: snapshot.seq, terminals: snapshot.terminals))
            }
            return updates
        case "event":
            guard let event = decodeEvent(params) else { return [] }
            return [.event(seq: seq, event)]
        default:
            return []
        }
    }

    static func decodeEvent(_ params: [String: Any]) -> CoreEvent? {
        guard let type = params["type"] as? String else { return nil }
        let terminal = params["terminal"] as? String
        let data = params["data"] as? [String: Any] ?? [:]
        func decode<T: Decodable>(_ type: T.Type, _ value: Any?) -> T? {
            guard let value, !(value is NSNull),
                  let json = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]) else { return nil }
            return try? JSONDecoder().decode(T.self, from: json)
        }
        if type == "created" {
            guard let info = decode(TerminalInfo.self, data) else { return nil }
            return .created(info)
        }
        guard let terminal else { return .other(terminal: nil, type: type) }
        switch type {
        case "status":
            return .status(terminal: terminal, status: decode(CoreStatus.self, data["status"]), reported: (data["reported"] as? Bool) ?? false)
        case "turn":
            return .turn(terminal: terminal, turn: (data["turn"] as? NSNumber)?.uint64Value ?? 0, state: data["state"] as? String)
        case "title":
            return .title(terminal: terminal, title: (data["title"] as? String) ?? "")
        case "labels":
            return .labels(terminal: terminal, labels: (data["labels"] as? [String: String]) ?? [:])
        case "foreground":
            return .foreground(terminal: terminal, foreground: data.isEmpty ? nil : decode(CoreForeground.self, data))
        case "finished":
            return .finished(
                terminal: terminal,
                exitCode: (data["exit_code"] as? NSNumber)?.intValue,
                reason: data["reason"] as? String,
                finishedMs: (data["finished_ms"] as? NSNumber)?.uint64Value
            )
        case "removed": return .removed(terminal: terminal)
        case "lost": return .lost(terminal: terminal)
        case "restarted": return .restarted(terminal: terminal)
        default: return .other(terminal: terminal, type: type)
        }
    }

    static func request(id: Int, method: String, params: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": id, "method": method, "params": params])
    }

    static func readResponse(_ socket: LineSocket, id: Int) throws -> [String: Any] {
        while let line = socket.readLine() {
            if let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any], (object["id"] as? Int) == id {
                return object
            }
        }
        throw HerdrError.unavailable("herdr-core closed the connection")
    }

    static func result(of response: [String: Any]) throws -> Any {
        if let error = response["error"] as? [String: Any] {
            let data = error["data"] as? [String: Any] ?? [:]
            throw HerdrError(
                kind: (data["kind"] as? String) ?? "error",
                message: (error["message"] as? String) ?? "herdr-core error",
                hint: data["hint"] as? String
            )
        }
        return response["result"] ?? NSNull()
    }

    // MARK: Commands

    /// One request on a fresh connection, off the main thread.
    func call(_ method: String, _ params: [String: Any]) async throws -> Any {
        let path = socketPath
        let body = try Self.request(id: 1, method: method, params: params)
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let socket = try LineSocket(path: path)
                    defer { socket.close() }
                    try socket.writeLine(body)
                    let response = try Self.readResponse(socket, id: 1)
                    let result = try Self.result(of: response)
                    continuation.resume(returning: UncheckedBox(result))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }.value
    }

    func callDecoding<T: Decodable>(_ type: T.Type, _ method: String, _ params: [String: Any]) async throws -> T {
        let result = try await call(method, params)
        let data = try JSONSerialization.data(withJSONObject: result, options: [.fragmentsAllowed])
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw HerdrError(kind: "decode", message: "Unexpected \(method) result from herdr-core", hint: "\(error)")
        }
    }

    private struct ReadWire: Decodable {
        var text: String
        var how: String?
        var complete: Bool?
        var why: String?
    }

    public func read(terminal: String, lines: Int) async throws -> ReadOutput {
        let wire = try await callDecoding(ReadWire.self, "terminal.read", ["terminal": terminal, "lines": lines])
        return ReadOutput(text: wire.text, how: wire.how ?? "screen", complete: wire.complete ?? true, why: wire.why)
    }

    private struct SendWire: Decodable {
        var started: Bool?
        var turn: UInt64?
    }

    public func send(terminal: String, text: String, force: Bool) async throws -> SendOutput {
        let wire = try await callDecoding(SendWire.self, "terminal.send", ["terminal": terminal, "text": text, "force": force])
        return SendOutput(started: wire.started, turn: wire.turn ?? 0)
    }

    public func keys(terminal: String, keys: [String]) async throws {
        _ = try await call("terminal.keys", ["terminal": terminal, "keys": keys])
    }

    private struct InterruptWire: Decodable {
        var outcome: String
    }

    public func interrupt(terminal: String) async throws -> InterruptOutcome {
        let wire = try await callDecoding(InterruptWire.self, "terminal.interrupt", ["terminal": terminal])
        return InterruptOutcome(rawValue: wire.outcome) ?? .unknown
    }

    private struct TemplatesWire: Decodable {
        var templates: [TemplateInfo]
    }

    public func templates() async throws -> [TemplateInfo] {
        try await callDecoding(TemplatesWire.self, "templates.list", [:]).templates
    }

    public func serverVersion() async throws -> String {
        let result = try await call("server.status", [:])
        return ((result as? [String: Any])?["version"] as? String) ?? "?"
    }

    // MARK: herdr-app

    public func isHerdrAppRunning() async -> Bool {
        appRunning()
    }

    /// `herdr-app ls` → spaces, each with the terminals shown in it.
    public func spaces() async throws -> [HerdrSpace] {
        Self.spaces(inHerdrAppLs: try await runHerdrApp(["ls"]))
    }

    static func spaces(inHerdrAppLs data: Data) -> [HerdrSpace] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let spaces = object["spaces"] as? [[String: Any]] else { return [] }
        return spaces.compactMap { space in
            guard let id = space["id"] as? String else { return nil }
            let name = (space["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? id
            var terminals: [String] = []
            for tab in space["tabs"] as? [[String: Any]] ?? [] {
                terminals += addresses(in: tab["terminals"] as? [Any] ?? [])
            }
            return HerdrSpace(id: id, name: name, terminals: terminals, active: (space["active"] as? Bool) ?? false)
        }
    }

    /// Terminal addresses in a tab's `terminals`, sub-agents included, depth first. Herdr 0.1.14 lists
    /// `sub_agents` as bare addresses; objects shaped like a terminal entry are accepted too.
    private static func addresses(in terminals: [Any]) -> [String] {
        terminals.flatMap { entry -> [String] in
            if let address = entry as? String { return [address] }
            guard let t = entry as? [String: Any] else { return [] }
            let own = (t["terminal"] as? String).map { [$0] } ?? []
            return own + addresses(in: t["sub_agents"] as? [Any] ?? [])
        }
    }

    public func launch(_ request: LaunchRequest) async throws -> LaunchOutput {
        if request.withoutApp {
            guard let hcPath else {
                throw HerdrError(kind: "not_installed", message: "hc not found", hint: "Install herdr-core (hc) in ~/.local/bin.")
            }
            let output = try await Self.run(hcPath, Self.hcRunArguments(request, shell: ProcessRunner.loginShell()), tool: "hc")
            return LaunchOutput(terminal: Self.terminalAddress(inHerdrAppOutput: output))
        }
        var args: [String: Any] = ["folder": request.folder, "argv": request.argv]
        if !request.task.isEmpty { args["task"] = request.task }
        if let name = request.name, !name.isEmpty { args["name"] = name }
        let command: String
        if let spaceName = request.newSpaceName {
            command = "space.new"
            // space.new's `name` is the space's; it takes no terminal name.
            args.removeValue(forKey: "name")
            if !spaceName.isEmpty { args["name"] = spaceName }
        } else {
            command = "tab.new"
            if let space = request.space, !space.isEmpty { args["space"] = space }
        }
        let json = String(decoding: try JSONSerialization.data(withJSONObject: args), as: UTF8.self)
        let output = try await runHerdrApp(["do", command, json])
        return LaunchOutput(terminal: Self.terminalAddress(inHerdrAppOutput: output))
    }

    /// `hc run` for a launch without the app: kept like Herdr's panes, in a new tab of `request.space` (a new
    /// space when nil). A plain argv runs the way `herdr-app do tab.new` runs it — through a login shell, the
    /// task as its last argument, a shell left behind when it ends; a template gets its task from core.
    static func hcRunArguments(_ request: LaunchRequest, shell: String, newID: (String) -> String = HerdrLabels.newID) -> [String] {
        let space = request.space.flatMap { $0.isEmpty ? nil : $0 } ?? newID("sp")
        var args = ["run", "--bg", "--keep", "--no-parent", "--json", "--cwd", request.folder,
                    "--label", "\(HerdrLabels.space)=\(space)", "--label", "\(HerdrLabels.tab)=\(newID("tb"))"]
        if let name = request.name, !name.isEmpty { args += ["--name", name] }
        args.append("--")
        let task = request.task.isEmpty ? [] : [request.task]
        if request.template {
            args += request.argv + task
        } else {
            args += [shell, "-lic", #""$@"; exec "$0" -li"#, shell] + request.argv + task
        }
        return args
    }

    public func renameSpace(id: String, name: String) async throws {
        let json = String(decoding: try JSONSerialization.data(withJSONObject: ["id": id, "name": name]), as: UTF8.self)
        _ = try await runHerdrApp(["do", "space.rename", json])
    }

    public func focus(terminal: String) async throws {
        // Started outside Herdr (e.g. `hc run claude` in Ghostty): give it a pane first.
        if let shown = try? await terminalsShownInHerdr(), !shown.contains(terminal) {
            let keep = String(decoding: try JSONSerialization.data(withJSONObject: ["terminal": terminal, "place": "tab"]), as: UTF8.self)
            _ = try await runHerdrApp(["do", "terminal.keep", keep])
        }
        let json = String(decoding: try JSONSerialization.data(withJSONObject: ["terminal": terminal]), as: UTF8.self)
        _ = try await runHerdrApp(["do", "agent.focus", json])
        // Verified on Herdr 0.1.14: agent.focus selects the pane but doesn't bring the window forward.
        activateApp()
    }

    /// Terminals that have a pane (or show as a sub-agent) in the Herdr window, from `herdr-app ls`.
    func terminalsShownInHerdr() async throws -> Set<String> {
        Self.terminalsShown(inHerdrAppLs: try await runHerdrApp(["ls"]))
    }

    static func terminalsShown(inHerdrAppLs data: Data) -> Set<String> {
        Set(spaces(inHerdrAppLs: data).flatMap(\.terminals))
    }

    /// Finds a terminal address (`t7`) in a herdr-app command result, wherever it sits.
    static func terminalAddress(inHerdrAppOutput data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return nil }
        func search(_ value: Any) -> String? {
            if let dict = value as? [String: Any] {
                for key in ["terminal", "address", "agent"] {
                    if let s = dict[key] as? String, s.range(of: #"^([a-z0-9_.-]+/)?t[0-9a-z]+$"#, options: .regularExpression) != nil {
                        return s
                    }
                }
                for (_, nested) in dict { if let found = search(nested) { return found } }
            } else if let array = value as? [Any] {
                for nested in array { if let found = search(nested) { return found } }
            }
            return nil
        }
        return search(object)
    }

    private func runHerdrApp(_ arguments: [String]) async throws -> Data {
        guard let path = herdrAppPath else {
            throw HerdrError(kind: "not_installed", message: "herdr-app not found", hint: "Install Herdr (herdr-app) in ~/.local/bin or /Applications.")
        }
        return try await Self.run(path, arguments, tool: "herdr-app")
    }

    /// Runs herdr-app or hc; both report failures as `{"error": {kind, message, hint}}`.
    static func run(_ path: String, _ arguments: [String], tool: String) async throws -> Data {
        let output: ProcessRunner.Output
        do {
            output = try await ProcessRunner.run(path, arguments)
        } catch {
            throw HerdrError(kind: "app_command_failed", message: "\(error)")
        }
        if let error = herdrAppError(output.stdout) ?? herdrAppError(output.stderr) { throw error }
        guard output.status == 0 else {
            let message = output.errorText.trimmingCharacters(in: .whitespacesAndNewlines)
            throw HerdrError(kind: "app_command_failed", message: message.isEmpty ? "\(tool) exited with \(output.status)" : message)
        }
        return output.stdout
    }

    static func herdrAppError(_ data: Data) -> HerdrError? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] as? [String: Any] else { return nil }
        return HerdrError(
            kind: (error["kind"] as? String) ?? "error",
            message: (error["message"] as? String) ?? "herdr-app error",
            hint: error["hint"] as? String
        )
    }
}

private struct UncheckedBox: @unchecked Sendable {
    let value: Any
    init(_ value: Any) { self.value = value }
}

/// Minimal blocking line-oriented Unix socket.
final class LineSocket: @unchecked Sendable {
    private let fd: Int32
    private var buffer = Data()
    private let lock = NSLock()
    private var closed = false

    init(path: String) throws {
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw HerdrError.unavailable("socket() failed") }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxLength = MemoryLayout.size(ofValue: addr.sun_path)
        guard path.utf8.count < maxLength else {
            Darwin.close(fd)
            throw HerdrError.unavailable("socket path too long")
        }
        withUnsafeMutablePointer(to: &addr.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: maxLength) { _ = strncpy($0, path, maxLength) }
        }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            Darwin.close(fd)
            throw HerdrError(kind: "unavailable", message: "herdr-core isn't running", hint: "Start it with `hc server start`.")
        }
    }

    func writeLine(_ data: Data) throws {
        var payload = data
        payload.append(0x0A)
        try payload.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let n = write(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset)
                if n <= 0 { throw HerdrError.unavailable("write to herdr-core failed") }
                offset += n
            }
        }
    }

    /// Next line without its newline; nil at EOF or error.
    func readLine() -> Data? {
        var chunk = [UInt8](repeating: 0, count: 65536)
        while true {
            if let index = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<index]
                buffer.removeSubrange(buffer.startIndex...index)
                return Data(line)
            }
            let n = read(fd, &chunk, chunk.count)
            if n <= 0 { return nil }
            buffer.append(contentsOf: chunk[0..<n])
        }
    }

    /// Unblocks a pending read from another thread.
    func shutdown() {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else { return }
        Darwin.shutdown(fd, SHUT_RDWR)
    }

    func close() {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else { return }
        closed = true
        Darwin.close(fd)
    }
}
