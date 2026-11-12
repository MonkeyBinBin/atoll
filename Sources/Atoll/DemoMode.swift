import AtollCore
import Foundation

/// Staged agents for README screenshots: `ATOLL_DEMO=1` swaps every source for this one, git for canned
/// summaries, and settings for their own UserDefaults suite. Projects, output and diffs are made up.
enum DemoMode {
    static var isOn: Bool { ProcessInfo.processInfo.environment["ATOLL_DEMO"] == "1" }
    static let defaultsSuite = "local.atoll.demo"

    static let home = NSHomeDirectory()
    static let webApp = home + "/Projects/web-app"
    static let api = home + "/Projects/api-server"
    static let scripts = home + "/Projects/scripts"

    static let spaces = [
        HerdrSpace(id: "spdemoweb", name: "web-app", terminals: ["t1", "t3"]),
        HerdrSpace(id: "spdemoapi", name: "api-server", terminals: ["t2", "t4"]),
    ]
}

final class DemoClient: HerdrClient, @unchecked Sendable {
    @MainActor private var onUpdate: (@MainActor (ClientUpdate) -> Void)?
    @MainActor private var seq: UInt64 = 1

    @MainActor func start(onUpdate: @escaping @MainActor (ClientUpdate) -> Void) {
        self.onUpdate = onUpdate
        onUpdate(.connected(CoreHello(generation: 1, version: "0.1.20", methods: AgentStore.requiredMethods)))
        onUpdate(.snapshot(seq: 1, terminals: [
            Self.term("t1", Self.status("working", "claude-code"), DemoMode.webApp),
            Self.term("t2", Self.status("working", "codex"), DemoMode.api),
            Self.term("t3", Self.status("working", "claude-code"), DemoMode.webApp + "/../web-app.worktrees/checkout-form", name: "checkout-form"),
            Self.term("t4", Self.status("working", "claude-code"), DemoMode.api),
            Self.term("t5", Self.status("working", "codex"), DemoMode.scripts),
        ]))
        // Turns end one after another, so the timeline, summaries and last words fill in.
        let script: [(Double, String, CoreStatus)] = [
            (0.8, "t5", Self.status("idle", "codex", msg: "Renamed the backup script and added a --dry-run flag.")),
            (1.6, "t4", Self.status("done", "claude-code", msg: "Added cursor pagination to GET /orders; the old offset param still works.")),
            (2.4, "t3", Self.status("done", "claude-code", msg: "Checkout form validation is done — all 42 tests pass.")),
            (3.2, "t1", Self.status("blocked", "claude-code", kind: "permission")),
        ]
        // herdr-core beats every 15 s; without it the island would go grey after `staleAfter`.
        Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.onUpdate?(.heartbeat(seq: self.seq))
            }
        }
        for (delay, terminal, status) in script {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                MainActor.assumeIsolated { self?.emit(terminal, status) }
            }
        }
    }

    @MainActor private func emit(_ terminal: String, _ status: CoreStatus) {
        seq += 1
        onUpdate?(.event(seq: seq, .status(terminal: terminal, status: status, reported: true)))
    }

    @MainActor func reconnect() {}
    @MainActor func stop() {}

    func read(terminal: String, lines: Int) async throws -> ReadOutput {
        ReadOutput(text: DemoScreens.screen(for: terminal), how: "history")
    }

    func send(terminal: String, text: String, force: Bool) async throws -> SendOutput { SendOutput(started: true) }
    func keys(terminal: String, keys: [String]) async throws {}
    func interrupt(terminal: String) async throws -> InterruptOutcome { .stopped }
    func templates() async throws -> [TemplateInfo] { [] }
    func isHerdrAppRunning() async -> Bool { true }
    func spaces() async throws -> [HerdrSpace] { DemoMode.spaces }
    func launch(_ request: LaunchRequest) async throws -> LaunchOutput {
        throw HerdrError(kind: "demo", message: "Demo mode doesn't launch agents")
    }
    func focus(terminal: String) async throws {}

    private static func status(_ state: String, _ app: String, kind: String? = nil, msg: String? = nil) -> CoreStatus {
        CoreStatus(state: state, app: app, kind: kind, msg: msg)
    }

    private static func term(_ address: String, _ status: CoreStatus, _ cwd: String, name: String? = nil) -> TerminalInfo {
        let path = (cwd as NSString).standardizingPath
        return TerminalInfo(address: address, name: name, argv: [status.app ?? "claude"], cwd: path,
                            status: status, statusMs: UInt64((Date().timeIntervalSince1970 - 180) * 1000), reported: true, turn: 3)
    }
}

/// Canned git answers per project: each turn "changed" a fixed set of files.
struct DemoGit: ChangeProbing, ChangeInspecting, WorkingTreeProbing {
    func baseline(in directory: String) async -> TurnBaseline? {
        TurnBaseline(toplevel: directory, head: "a1b2c3d", dirty: false, untracked: [])
    }

    func summary(in directory: String, since baseline: TurnBaseline?) async -> ChangeSummary? {
        let files = Self.files(for: directory)
        let tracked = files.filter { $0.kind != .untracked }
        return ChangeSummary(
            insertions: tracked.compactMap(\.insertions).reduce(0, +),
            deletions: tracked.compactMap(\.deletions).reduce(0, +),
            files: tracked.count, untracked: files.count - tracked.count,
            baseline: .turnStart, toplevel: directory, baseCommit: "a1b2c3d",
            newFiles: files.filter { $0.kind == .untracked }.map(\.path)
        )
    }

    func toplevel(in directory: String) async -> String? { directory }

    func files(for summary: ChangeSummary) async -> [ChangedFile]? { Self.files(for: summary.toplevel) }

    func diff(of file: ChangedFile, for summary: ChangeSummary) async -> FileDiff? {
        FileDiff(lines: [
            "@@ -12,9 +12,21 @@ export function CheckoutForm({ onSubmit }: Props) {",
            "   const [values, setValues] = useState(initialValues)",
            "-  const [error, setError] = useState<string | null>(null)",
            "+  const { errors, validate } = useValidation(checkoutSchema)",
            " ",
            "   function handleSubmit(event: FormEvent) {",
            "     event.preventDefault()",
            "-    if (!values.email) return setError('Email is required')",
            "+    const result = validate(values)",
            "+    if (!result.ok) return",
            "     onSubmit(values)",
            "   }",
            "@@ -40,6 +52,12 @@ export function CheckoutForm({ onSubmit }: Props) {",
            "       <Field label=\"Email\" name=\"email\" value={values.email} onChange={update} />",
            "+      {errors.email && <FieldError>{errors.email}</FieldError>}",
            "       <Field label=\"Card number\" name=\"card\" value={values.card} onChange={update} />",
            "+      {errors.card && <FieldError>{errors.card}</FieldError>}",
        ])
    }

    private static func files(for directory: String) -> [ChangedFile] {
        if directory.contains("checkout-form") {
            return [
                ChangedFile(path: "src/checkout/CheckoutForm.tsx", kind: .modified, insertions: 58, deletions: 21),
                ChangedFile(path: "src/checkout/useValidation.ts", kind: .added, insertions: 41, deletions: 0),
                ChangedFile(path: "src/checkout/schema.ts", kind: .modified, insertions: 12, deletions: 4),
                ChangedFile(path: "src/checkout/CheckoutForm.test.tsx", kind: .modified, insertions: 17, deletions: 9),
                ChangedFile(path: "src/ui/FieldError.tsx", kind: .renamed(from: "src/ui/ErrorText.tsx"), insertions: 0, deletions: 0),
                ChangedFile(path: "docs/checkout.md", kind: .untracked),
            ]
        }
        if directory.hasSuffix("api-server") {
            return [
                ChangedFile(path: "src/routes/orders.ts", kind: .modified, insertions: 34, deletions: 12),
                ChangedFile(path: "src/db/pagination.ts", kind: .added, insertions: 27, deletions: 0),
                ChangedFile(path: "test/orders.test.ts", kind: .modified, insertions: 22, deletions: 3),
            ]
        }
        return [ChangedFile(path: "backup.sh", kind: .modified, insertions: 9, deletions: 2)]
    }
}

enum DemoScreens {
    static let rule = String(repeating: "─", count: 120)
    static let dashed = String(repeating: "╌", count: 120)

    static func screen(for terminal: String) -> String {
        switch terminal {
        case "t1": claudePermission
        case "t3": claudeDone
        case "t2": codexWorking
        default: "⏺ Done."
        }
    }

    static let claudePermission = [
        "❯ Fix the flaky cart test and make sure the whole suite passes",
        "",
        "⏺ The cart test is flaky because it depends on the current time. I'll freeze the clock",
        "  with vi.useFakeTimers() and re-run the suite.",
        "",
        "⏺ Update(src/cart/cart.test.ts)",
        "  ⎿  Updated src/cart/cart.test.ts with 4 additions and 1 removal",
        "",
        "⏺ Now let me run the full test suite to confirm nothing else breaks.",
        "",
        rule,
        " Bash command",
        dashed,
        " npm test -- --run",
        dashed,
        " Run the full test suite once",
        "",
        " Do you want to proceed?",
        " ❯ 1. Yes",
        "   2. Yes, and don't ask again for npm test commands in this project",
        "   3. No",
        "",
        " Esc to cancel · Tab to amend",
    ].joined(separator: "\n")

    static let claudeDone = [
        "❯ Add validation to the checkout form: required email, card number check, inline errors",
        "",
        "⏺ I'll add a small useValidation hook driven by a schema, then wire inline errors into the form.",
        "",
        "⏺ Write(src/checkout/useValidation.ts)",
        "  ⎿  Wrote 41 lines to src/checkout/useValidation.ts",
        "",
        "⏺ Update(src/checkout/CheckoutForm.tsx)",
        "  ⎿  Updated src/checkout/CheckoutForm.tsx with 58 additions and 21 removals",
        "",
        "⏺ Bash(npm test -- --run src/checkout)",
        "  ⎿  ✓ src/checkout/CheckoutForm.test.tsx (42 tests) 812ms",
        "     Test Files  1 passed (1)",
        "",
        "⏺ Checkout form validation is done — all 42 tests pass. Errors show under each field",
        "  and the submit button stays disabled until the form is valid.",
        "",
        "❯ ",
    ].joined(separator: "\n")

    static let codexWorking = [
        "› Profile the /orders endpoint and fix the slow query",
        "",
        "• Explored",
        "  └ Read orders.ts, pagination.ts",
        "",
        "• The slow path is a missing index on orders(customer_id, created_at). Adding a migration.",
        "",
        "• Working (2m 14s • esc to interrupt)",
    ].joined(separator: "\n")
}
