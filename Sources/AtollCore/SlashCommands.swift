import Foundation

/// Something the reply box can complete: a Claude Code slash command or skill (`/name`), a Codex
/// slash command (`/name`) or a Codex skill mention (`$name`).
/// Read from definition files on disk, so it can differ from what the running agent actually loaded
/// (a plugin toggled since, a skill added after the session started). Completion only, never sent on its own.
public struct SlashCommand: Equatable, Sendable, Identifiable {
    public enum Source: Equatable, Sendable {
        case builtIn
        case personal
        case project
        case plugin(String)
    }

    public var trigger: Character
    public var name: String
    public var description: String?
    public var argumentHint: String?
    public var source: Source

    public init(trigger: Character = "/", name: String, description: String? = nil, argumentHint: String? = nil, source: Source) {
        self.trigger = trigger
        self.name = name
        self.description = description
        self.argumentHint = argumentHint
        self.source = source
    }

    /// What gets typed: `/commit`, `$imagegen`.
    public var token: String { "\(trigger)\(name)" }
    public var id: String { token }
}

// MARK: - Catalog

/// Collects completable commands for one agent from the files its CLI reads them from.
public enum SlashCommandCatalog {
    public static func load(tool: AgentTool, cwd: String?, home: String = NSHomeDirectory()) -> [SlashCommand] {
        let projects = projectDirectories(from: cwd, home: home)
        let all: [SlashCommand]
        switch tool {
        case .claudeCode: all = claudeCode(projects: projects, home: home)
        case .codex: all = codex(projects: projects, home: home)
        case .generic: return []
        }
        // First definition of a name wins: callers list sources in precedence order.
        var seen: Set<String> = []
        return all.filter { seen.insert($0.token).inserted }
    }

    /// Claude Code: built-ins, `~/.claude`, `.claude/` from cwd up to the repo root, enabled plugins.
    /// A skill and a command of the same name → the skill (skills are listed first at each level).
    static func claudeCode(projects: [String], home: String) -> [SlashCommand] {
        let user = join(home, ".claude")
        var result = claudeBuiltIns
        result += skills(in: join(user, "skills"), trigger: "/", source: .personal)
        result += commands(in: join(user, "commands"), source: .personal)
        for dir in projects {
            result += skills(in: join(dir, ".claude/skills"), trigger: "/", source: .project)
            result += commands(in: join(dir, ".claude/commands"), source: .project)
        }
        for plugin in enabledPlugins(home: home, projects: projects) {
            result += pluginCommands(plugin)
        }
        return result
    }

    /// Per the plugin manifest reference: `skills` paths (a skill folder or a folder of skills) add to
    /// the default `skills/`; `commands` (paths to `.md` files or folders, or a name → {source|content}
    /// map) replaces the default `commands/`.
    static func pluginCommands(_ plugin: PluginLocation) -> [SlashCommand] {
        let source = SlashCommand.Source.plugin(plugin.name)
        let manifest = readJSON(join(plugin.path, ".claude-plugin/plugin.json")) ?? [:]
        func resolve(_ relative: String) -> String {
            URL(fileURLWithPath: join(plugin.path, relative)).standardizedFileURL.path
        }
        func listed(_ key: String) -> [String] {
            (manifest[key] as? [String]) ?? (manifest[key] as? String).map { [$0] } ?? []
        }

        var result: [SlashCommand] = []
        for full in (["skills"] + listed("skills")).map(resolve) {
            if FileManager.default.fileExists(atPath: join(full, "SKILL.md")) {
                result += skills(in: (full as NSString).deletingLastPathComponent, trigger: "/", source: source,
                                 prefix: plugin.name, only: (full as NSString).lastPathComponent)
            } else {
                result += skills(in: full, trigger: "/", source: source, prefix: plugin.name)
            }
        }

        if let map = manifest["commands"] as? [String: [String: Any]] {
            for (name, entry) in map.sorted(by: { $0.key < $1.key }) {
                let doc = (entry["source"] as? String).flatMap { readHead(resolve($0)) }.map(Frontmatter.parse)
                    ?? Frontmatter(body: entry["content"] as? String ?? "")
                var command = command(trigger: "/", name: "\(plugin.name):\(name)", doc: doc, source: source)
                if let description = entry["description"] as? String { command.description = collapse(description) }
                if let hint = entry["argumentHint"] as? String { command.argumentHint = collapse(hint) }
                result.append(command)
            }
            return result
        }
        let commandPaths = manifest["commands"] == nil ? ["commands"] : listed("commands")
        for full in commandPaths.map(resolve) {
            if full.hasSuffix(".md") {
                result += commands(in: (full as NSString).deletingLastPathComponent, source: source,
                                   prefix: plugin.name, only: (full as NSString).lastPathComponent)
            } else {
                result += commands(in: full, source: source, prefix: plugin.name)
            }
        }
        return result
    }

    /// Codex: slash built-ins plus `$` skills from `~/.agents/skills`, the older `~/.codex/skills`
    /// (and its bundled `.system`), and `.agents/skills` from cwd up to the repo root.
    static func codex(projects: [String], home: String) -> [SlashCommand] {
        var result = codexBuiltIns
        result += skills(in: join(home, ".agents/skills"), trigger: "$", source: .personal)
        result += skills(in: join(home, ".codex/skills"), trigger: "$", source: .personal)
        for dir in projects {
            result += skills(in: join(dir, ".agents/skills"), trigger: "$", source: .project)
        }
        result += skills(in: join(home, ".codex/skills/.system"), trigger: "$", source: .builtIn)
        return result
    }

    /// cwd and each parent up to the repo root (the first directory holding `.git`), nearest first.
    /// Outside a repo only cwd itself; never home, whose `.claude` is the personal level.
    static func projectDirectories(from cwd: String?, home: String) -> [String] {
        guard let cwd, !cwd.isEmpty else { return [] }
        let start = URL(fileURLWithPath: cwd).standardizedFileURL.path
        let homePath = URL(fileURLWithPath: home).standardizedFileURL.path
        var dirs: [String] = []
        var dir = start
        while dir != homePath {
            dirs.append(dir)
            if FileManager.default.fileExists(atPath: join(dir, ".git")) { return dirs }
            let parent = (dir as NSString).deletingLastPathComponent
            if parent == dir { break }
            dir = parent
        }
        return start == homePath ? [] : [start]
    }

    // MARK: Files

    /// `<dir>/<skill>/SKILL.md` → name from frontmatter `name`, else the directory name.
    static func skills(
        in dir: String, trigger: Character, source: SlashCommand.Source, prefix: String? = nil, only: String? = nil
    ) -> [SlashCommand] {
        let entries = only.map { [$0] } ?? (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        return entries.sorted().compactMap { entry in
            guard !entry.hasPrefix("."), let text = readHead(join(join(dir, entry), "SKILL.md")) else { return nil }
            let doc = Frontmatter.parse(text)
            guard doc.fields["user-invocable"]?.lowercased() != "false" else { return nil }
            let base = doc.fields["name"].flatMap { $0.isEmpty ? nil : $0 } ?? entry
            return command(trigger: trigger, name: prefix.map { "\($0):\(base)" } ?? base, doc: doc, source: source)
        }
    }

    /// `<dir>/**/*.md` → path relative to `dir` without `.md`, subdirectories joined by `:`.
    static func commands(in dir: String, source: SlashCommand.Source, prefix: String? = nil, only: String? = nil) -> [SlashCommand] {
        var paths: [String] = []
        if let only {
            paths = [String(only.dropLast(3))]
        } else {
            let root = URL(fileURLWithPath: dir).standardizedFileURL
            guard let walker = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            ) else { return [] }
            for case let url as URL in walker where url.pathExtension == "md" {
                let relative = url.standardizedFileURL.path.dropFirst(root.path.count + 1)
                paths.append(String(relative.dropLast(3)))
            }
        }
        return paths.sorted().compactMap { path in
            guard let text = readHead(join(dir, path + ".md")) else { return nil }
            let doc = Frontmatter.parse(text)
            guard doc.fields["user-invocable"]?.lowercased() != "false" else { return nil }
            let base = path.replacingOccurrences(of: "/", with: ":")
            return command(trigger: "/", name: prefix.map { "\($0):\(base)" } ?? base, doc: doc, source: source)
        }
    }

    static func command(trigger: Character, name: String, doc: Frontmatter, source: SlashCommand.Source) -> SlashCommand {
        let description = doc.fields["description"].flatMap { $0.isEmpty ? nil : $0 } ?? doc.firstBodyLine
        return SlashCommand(
            trigger: trigger, name: name,
            description: description.map(collapse),
            argumentHint: doc.fields["argument-hint"].flatMap { $0.isEmpty ? nil : collapse($0) },
            source: source
        )
    }

    /// Frontmatter sits at the top; a long skill body isn't worth reading.
    static func readHead(_ path: String, bytes: Int = 16_384) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: bytes) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Plugins

    struct PluginLocation: Equatable {
        var name: String
        var path: String
    }

    /// Plugins installed for the user (or for one of these project directories) and switched on in
    /// `enabledPlugins` of `~/.claude/settings.json`, overridden by the repo's `.claude/settings{,.local}.json`.
    static func enabledPlugins(home: String, projects: [String]) -> [PluginLocation] {
        let pluginsDir = join(home, ".claude/plugins")
        guard let installed = readJSON(join(pluginsDir, "installed_plugins.json"))?["plugins"] as? [String: Any] else { return [] }
        var enabled = enabledMap(join(home, ".claude/settings.json"))
        if let root = projects.last {
            enabled.merge(enabledMap(join(root, ".claude/settings.json"))) { $1 }
            enabled.merge(enabledMap(join(root, ".claude/settings.local.json"))) { $1 }
        }
        let projectSet = Set(projects)
        return installed.keys.sorted().compactMap { key in
            guard enabled[key] == true, let entries = installed[key] as? [[String: Any]] else { return nil }
            let entry = entries.first { entry in
                (entry["scope"] as? String) == "user" || (entry["projectPath"] as? String).map(projectSet.contains) == true
            }
            guard let path = entry?["installPath"] as? String else { return nil }
            let name = key.split(separator: "@", maxSplits: 1).first.map(String.init) ?? key
            return PluginLocation(name: name, path: path)
        }
    }

    static func enabledMap(_ path: String) -> [String: Bool] {
        (readJSON(path)?["enabledPlugins"] as? [String: Bool]) ?? [:]
    }

    static func readJSON(_ path: String) -> [String: Any]? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    // MARK: Built-ins

    /// Built-in commands, bundled skills and workflows from code.claude.com/docs/en/commands (menu-hidden
    /// ones left out, aliases included so a fully typed alias matches exactly). Refresh when Claude Code adds some.
    static let claudeBuiltIns: [SlashCommand] = builtIns([
        ("add-dir", "<path>", "Add a working directory for file access during the current session"),
        ("advisor", "[model|off]", "Enable or disable the advisor tool, which consults a second model for guidance at key mom…"),
        ("agents", nil, "Print a reminder to ask Claude to create or manage subagents, or to edit .claude/agents/…"),
        ("artifact-capabilities", nil, "Load the reference for the runtime capabilities a published artifact can use, such as cal…"),
        ("artifact-diagramming", nil, "Load diagramming guidance for Claude to follow in artifacts: when a diagram helps, what t…"),
        ("artifacts", nil, "List the artifacts you own or that are shared with you, then attach one to the session, o…"),
        ("auto-mode-setup", nil, "Draft autoMode.environment entries from your project and recent sessions, then review the…"),
        ("autocompact", "[auto|<tokens>]", "Set the auto-compact window: how full the context window gets before Claude Code compacts…"),
        ("autofix-pr", "[prompt]", "Spawn a cloud session that watches the current branch's PR and pushes fixes when CI fails…"),
        ("background", "[prompt]", "Detach the current session to run as a background agent and free this terminal"),
        ("bg", "[prompt]", "Alias of /background"),
        ("batch", "<instruction>", "Orchestrate large-scale changes across a codebase in parallel"),
        ("branch", "[name]", "Create a branch of the current conversation at this point, so you can try a different dir…"),
        ("btw", "[question]", "Ask a side question about the current session without adding to the conversation"),
        ("bug", "[report]", "Report a bug or share your conversation"),
        ("share", "[report]", "Alias of /bug"),
        ("feedback", "[report]", "Alias of /bug"),
        ("cd", "<path>", "Move this session to a new working directory, keeping the conversation"),
        ("chrome", nil, "Configure Claude in Chrome settings"),
        ("claude-api", "[migrate|upgrade|api-version|managed-agents-onboard|managed-agents-secure|prompt-audit|cost-optimize|latency-optimize|build-eval|hillclimb|preserved-thinking-migration]", "Load Claude API and Managed Agents reference material for your project's language"),
        ("claude-in-chrome", "[task]", "Have Claude carry out a task in your browser, such as testing a page, filling a form, or…"),
        ("clear", "[name]", "Start a new conversation with empty context"),
        ("reset", "[name]", "Alias of /clear"),
        ("new", "[name]", "Alias of /clear"),
        ("code-review", "[low|medium|high|xhigh|max|ultra] [--fix] [--comment] [--max-findings n|all|default] [pr#|branch|path]", "Review the current diff, or a PR number, branch, or path you pass, for correctness bugs"),
        ("review", "[low|medium|high|xhigh|max|ultra] [--fix] [--comment] [--max-findings n|all|default] [pr#|branch|path]", "Alias of /code-review"),
        ("color", "[color|default]", "Set the prompt bar color for the current session"),
        ("compact", "[instructions]", "Free up context by summarizing the conversation so far"),
        ("config", "[key=value ...]", "Open the Settings interface to adjust theme, model, output style, and other preferences"),
        ("settings", "[key=value ...]", "Alias of /config"),
        ("context", "[all]", "Visualize current context usage as a colored grid"),
        ("copy", "[N]", "Copy the last assistant response to clipboard"),
        ("cost", nil, "Alias for /usage"),
        ("dataviz", "[request]", "Design guidance for charts, graphs, and dashboards"),
        ("debug", "[description]", "Enable debug logging for the current session and troubleshoot issues by reading the sessi…"),
        ("deep-research", "<question>", "Fan out web searches on a question, fetch and cross-check sources, and synthesize a cited…"),
        ("design", "[brief]", "Draft UI mockups, screen flows, landing pages, or posters as artboards on one canvas, pub…"),
        ("design-login", nil, "Authorize design-system access for /design-sync with your claude.ai account"),
        ("design-sync", "[hint]", "Convert your repo's React design system and upload it to Claude Design, so designs it pro…"),
        ("desktop", nil, "Continue the current session in the Claude Code Desktop app"),
        ("app", nil, "Alias of /desktop"),
        ("diff", nil, "Review the changes in your working tree, including the edits Claude has made so far"),
        ("doctor", "[prompt-audit [path]]", "Run a setup checkup that diagnoses installation, settings, extension, and CLAUDE.md probl…"),
        ("checkup", "[prompt-audit [path]]", "Alias of /doctor"),
        ("effort", "[level|auto|status|ultracode [on|off]]", "Set the effort level: low to xhigh, max, or auto; status prints it"),
        ("exit", nil, "Exit the CLI"),
        ("quit", nil, "Alias of /exit"),
        ("export", "[filename]", "Export the current conversation as plain text"),
        ("fast", "[on|off]", "Toggle fast mode on or off"),
        ("fewer-permission-prompts", nil, "Scan your transcripts for common read-only Bash and MCP tool calls, then add a prioritize…"),
        ("focus", nil, "Toggle the focus view, which shows only your last prompt, a one-line tool-call summary wi…"),
        ("fork", "[prompt]", "Copy the current conversation into a new background session and keep working here"),
        ("goal", "[condition|clear]", "Set a goal: Claude keeps working across turns until the condition is met or the goal clea…"),
        ("help", nil, "Show help and available commands"),
        ("hooks", nil, "View hook configurations"),
        ("ide", nil, "Manage IDE integrations and show status"),
        ("import", "[codex|gemini|cursor] [--dry-run] [--yes]", "Bring configuration from OpenAI Codex, Google Gemini CLI, or Cursor on your machine into…"),
        ("init", nil, "Initialize project with a CLAUDE.md guide"),
        ("insights", nil, "Generate an HTML report analyzing your recent sessions on this machine: which projects yo…"),
        ("install-github-app", nil, "Install the Claude GitHub App for a repository, with an optional step to set up GitHub Ac…"),
        ("install-slack-app", nil, "Install the Claude Slack app"),
        ("keybindings", nil, "Open your keyboard shortcuts file"),
        ("list-agents", nil, "List the subagents, agent team teammates, and other Claude Code sessions Claude can messa…"),
        ("login", nil, "Sign in to your Anthropic account"),
        ("logout", nil, "Sign out from your Anthropic account"),
        ("loop", "[interval] [prompt]", "Run a prompt repeatedly while the session stays open"),
        ("proactive", "[interval] [prompt]", "Alias of /loop"),
        ("mcp", "[reconnect (<server>|all)|enable|disable [<server>|all]]", "Manage MCP server connections and OAuth authentication"),
        ("memory", nil, "Edit CLAUDE.md files, enable or disable auto memory, and view auto memory entries"),
        ("mobile", nil, "Show QR code to download the Claude mobile app"),
        ("ios", nil, "Alias of /mobile"),
        ("android", nil, "Alias of /mobile"),
        ("model", "[model]", "Switch the AI model and save it as your default for new sessions"),
        ("output-style", "[style]", "List output styles or switch to one, for example /output-style concise"),
        ("passes", nil, "Share a free week of Claude Code with friends"),
        ("permissions", nil, "Manage allow, ask, and deny rules for tool permissions"),
        ("allowed-tools", nil, "Alias of /permissions"),
        ("plan", "[description]", "Enter plan mode directly from the prompt"),
        ("plugin", "[subcommand]", "Manage Claude Code plugins"),
        ("plugin-authoring", nil, "Load the reference Claude works from to write a mod"),
        ("powerup", nil, "Discover Claude Code features through quick interactive lessons with animated demos"),
        ("privacy-settings", nil, "View and update your privacy settings"),
        ("radio", nil, "Open Claude FM lo-fi radio in your browser"),
        ("rate-limit-options", nil, "Show ways to keep working when a claude.ai usage limit blocks a request: wait and continu…"),
        ("recap", nil, "Generate a one-line summary of the current session on demand"),
        ("release-notes", nil, "View the changelog in an interactive version picker"),
        ("reload-plugins", "[--force]", "Reload all active plugins to apply pending changes without restarting"),
        ("reload-skills", nil, "Re-scan skill and command directories so skills added or changed on disk during the sessi…"),
        ("remote-control", nil, "Make this session available for Remote Control from claude.ai"),
        ("rc", nil, "Alias of /remote-control"),
        ("remote-env", nil, "Choose the default cloud environment for cloud sessions you start from the CLI"),
        ("rename", "[name]", "Rename the current session and show the name on the prompt bar"),
        ("restart", nil, "Restart Claude Code and resume this session, which applies an installed update"),
        ("update", nil, "Alias of /restart"),
        ("resume", "[session]", "Resume a conversation by ID or name, or open the session picker"),
        ("continue", "[session]", "Alias of /resume"),
        ("rewind", nil, "Rewind the conversation and/or code to a previous point, or summarize from a selected mes…"),
        ("checkpoint", nil, "Alias of /rewind"),
        ("undo", nil, "Alias of /rewind"),
        ("run", nil, "Launch and drive your project's app to see a change working, not only passing tests"),
        ("run-skill-generator", nil, "Teach /run and /verify how to build, launch, and drive your project's app from a clean en…"),
        ("sandbox", nil, "Toggle sandbox mode"),
        ("schedule", "[description]", "Create, update, list, or run cloud scheduled tasks, formerly routines"),
        ("routines", "[description]", "Alias of /schedule"),
        ("scroll-speed", nil, "Adjust mouse wheel scroll speed interactively"),
        ("security-review", nil, "Analyze the changes on your current branch for security vulnerabilities"),
        ("simplify", "[target]", "Review the changed code for cleanup opportunities and apply the fixes"),
        ("skill-doctor", nil, "Show what each of your skills costs in context and how often it gets used, so you can fin…"),
        ("skills", nil, "List available skills"),
        ("slides", "[brief]", "Make a new presentation as a Claude Slides artifact filled from your brief, for example /…"),
        ("stats", nil, "Alias for /usage"),
        ("status", nil, "Open the Settings interface on the Status tab, showing version, model, account, and conne…"),
        ("statusline", nil, "Configure Claude Code's status line"),
        ("stickers", nil, "Order Claude Code stickers"),
        ("stop", nil, "Stop the background session you're attached to, or the one you send it to as a peek reply…"),
        ("subtask", "<task>", "Spawn a forked subagent: a background subagent that inherits the full conversation and wo…"),
        ("tasks", nil, "View and manage background work in the current session, including subagents that have fin…"),
        ("team-onboarding", nil, "Generate a team onboarding guide from your Claude Code usage history"),
        ("teleport", nil, "Pull a cloud session into this terminal"),
        ("terminal-setup", nil, "Install a Shift+Enter keybinding for newlines in VS Code, Cursor, Devin Desktop, Alacritt…"),
        ("theme", nil, "Change the color theme"),
        ("tui", "[default|fullscreen]", "Set the terminal UI renderer and relaunch into it with your conversation intact"),
        ("ultrareview", "[PR or branch]", "Run a deep, multi-agent code review in a cloud sandbox with ultrareview"),
        ("update-config", "[request]", "Describe a settings change, such as allowing a command, setting an environment variable,…"),
        ("upgrade", nil, "Open the upgrade page in your browser to switch to a higher plan tier"),
        ("usage", nil, "Show session cost, plan usage limits, and activity stats"),
        ("usage-credits", nil, "Configure usage credits, or request them from your admin, when you hit a limit"),
        ("verify", nil, "Confirm a code change does what it should by building your project's app, running it, and…"),
        ("voice", "[hold|tap|off]", "Toggle voice dictation, or enable it in a specific mode"),
        ("web-setup", nil, "Connect your GitHub account for cloud sessions using your local gh CLI credentials"),
        ("workflow-authoring", nil, "Load the reference for writing dynamic workflow scripts: the script API, resume behavior,…"),
        ("workflows", nil, "Open the workflow progress view to watch, pause, resume, or save running and completed wo…"),
    ])

    /// From the Codex CLI slash-command reference (learn.chatgpt.com/docs/developer-commands).
    static let codexBuiltIns: [SlashCommand] = builtIns([
        ("permissions", nil, "Set what Codex can do without asking first"),
        ("ide", nil, "Include open files, current selection, and other IDE context"),
        ("config", nil, "Search and change terminal preferences"),
        ("keymap", nil, "Remap TUI keyboard shortcuts"),
        ("vim", nil, "Toggle Vim mode for the composer"),
        ("agents", nil, "Open the agent command center"),
        ("subagents", nil, "Switch the active subagent thread"),
        ("apps", nil, "Browse apps (connectors) and insert them into your prompt"),
        ("plugins", nil, "Browse installed and discoverable plugins"),
        ("hooks", nil, "View and manage lifecycle hooks"),
        ("clear", nil, "Clear the terminal and start a fresh chat"),
        ("rename", nil, "Rename the current chat"),
        ("archive", nil, "Archive the current session"),
        ("delete", nil, "Permanently delete the current session"),
        ("compact", nil, "Summarize the visible chat to free tokens"),
        ("copy", nil, "Copy a response, code block, or quote"),
        ("diff", nil, "Show the Git diff, including files Git isn't tracking yet"),
        ("exit", nil, "Exit the CLI"),
        ("experimental", nil, "Toggle experimental features"),
        ("approve", nil, "Approve one retry of a recent auto review denial"),
        ("memories", nil, "Configure memory use and generation"),
        ("skills", nil, "Browse and use skills"),
        ("import", nil, "Import Claude Code or Cursor setup, projects, and chats"),
        ("feedback", nil, "Send logs to the Codex maintainers"),
        ("init", nil, "Generate an AGENTS.md scaffold in the current directory"),
        ("logout", nil, "Sign out of Codex"),
        ("mcp", nil, "List configured MCP tools"),
        ("mention", nil, "Attach a file to the chat"),
        ("model", nil, "Choose the active model (and reasoning effort, when available)"),
        ("presets", nil, "Save and run prompts or slash commands"),
        ("fast", nil, "Toggle a Fast service tier"),
        ("voice", nil, "Start or stop a voice conversation"),
        ("plan", nil, "Switch to plan mode and optionally send a prompt"),
        ("goal", nil, "Set, edit, pause, resume, view, or clear a task goal"),
        ("ps", nil, "Show background terminals and their recent output"),
        ("stop", nil, "Stop all background terminals"),
        ("fork", nil, "Fork the current chat into a new chat"),
        ("app", nil, "Continue the current session in the ChatGPT desktop app"),
        ("side", nil, "Start an ephemeral side chat"),
        ("btw", nil, "Start an ephemeral side chat"),
        ("raw", nil, "Toggle raw scrollback mode"),
        ("resume", nil, "Resume a saved chat from your session list"),
        ("new", nil, "Start a new chat inside the same CLI session"),
        ("quit", nil, "Exit the CLI"),
        ("review", nil, "Ask Codex to review your working tree"),
        ("status", nil, "Display session configuration and token usage"),
        ("usage", nil, "View account token usage or use a rate-limit reset"),
        ("debug-config", nil, "Print config layer and requirements diagnostics"),
        ("statusline", nil, "Configure TUI status-line fields"),
        ("title", nil, "Configure terminal window or tab title fields"),
        ("theme", nil, "Choose a syntax-highlighting theme"),
        ("pets", nil, "Choose or hide a terminal pet"),
        ("pet", nil, "Choose or hide a terminal pet"),
        ("tui", nil, "Choose the terminal mode for the next launch"),
        ("export", nil, "Export the conversation as Markdown"),
        ("recap", nil, "Generate a summary of the current conversation"),
        ("cd", nil, "Change the session's working directory"),
        ("pwd", nil, "Show the working directory"),
        ("cwd", nil, "Show the working directory"),
        ("worktree", nil, "Start or continue a chat in a managed Git worktree"),
        ("daemon", nil, "Open background server controls"),
        ("warnings", nil, "View retained warnings and diagnostics"),
    ])

    private static func builtIns(_ rows: [(String, String?, String)]) -> [SlashCommand] {
        rows.map { SlashCommand(name: $0.0, description: $0.2, argumentHint: $0.1, source: .builtIn) }
    }

    // MARK: Matching

    /// Prefix of the name, then prefix of its last `:` segment, then of any word, then anywhere.
    /// Ties: personal/project before plugins before built-ins, then by name.
    public static func matches(_ commands: [SlashCommand], query: String) -> [SlashCommand] {
        let q = query.lowercased()
        let scored: [(SlashCommand, Int)] = commands.compactMap { command in
            guard let score = score(command.name.lowercased(), q) else { return nil }
            return (command, score)
        }
        return scored.sorted { a, b in
            if a.1 != b.1 { return a.1 < b.1 }
            let ra = rank(a.0.source), rb = rank(b.0.source)
            if ra != rb { return ra < rb }
            return a.0.name < b.0.name
        }.map(\.0)
    }

    static func score(_ name: String, _ q: String) -> Int? {
        if q.isEmpty || name.hasPrefix(q) { return 0 }
        if let last = name.split(separator: ":").last, last.hasPrefix(q) { return 1 }
        if name.split(whereSeparator: { ":-_".contains($0) }).contains(where: { $0.hasPrefix(q) }) { return 2 }
        if name.contains(q) { return 3 }
        return nil
    }

    static func rank(_ source: SlashCommand.Source) -> Int {
        switch source {
        case .personal, .project: 0
        case .plugin: 1
        case .builtIn: 2
        }
    }

    // MARK: Helpers

    static func join(_ base: String, _ component: String) -> String {
        (base as NSString).appendingPathComponent(component)
    }

    static func collapse(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

// MARK: - Frontmatter

/// The YAML frontmatter subset skills use: `key: value`, quoted values, `>`/`|` block scalars and
/// indented continuation lines. Nested structures are skipped.
struct Frontmatter: Equatable {
    var fields: [String: String] = [:]
    var body: String = ""

    /// First non-empty body line without heading marks (Claude Code's fallback description).
    var firstBodyLine: String? {
        body.components(separatedBy: "\n")
            .lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { $0.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
    }

    static func parse(_ text: String) -> Frontmatter {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" })
        else { return Frontmatter(body: text) }

        var fields: [String: String] = [:]
        var key: String?
        var block: Character? // ">" folded, "|" literal
        var parts: [String] = []

        func flush() {
            if let key { fields[key] = unquote(parts.joined(separator: block == "|" ? "\n" : " ").trimmingCharacters(in: .whitespacesAndNewlines)) }
            key = nil
            block = nil
            parts = []
        }

        for line in lines[1..<end] {
            let indented = line.first == " " || line.first == "\t"
            if indented || line.trimmingCharacters(in: .whitespaces).isEmpty {
                if key != nil { parts.append(line.trimmingCharacters(in: .whitespaces)) }
                continue
            }
            flush()
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !name.hasPrefix("#") else { continue }
            key = name
            if let first = value.first, ">|".contains(first), value.dropFirst().allSatisfy({ "+-0123456789".contains($0) }) {
                block = first
            } else if !value.isEmpty {
                parts = [value]
            }
        }
        flush()
        return Frontmatter(fields: fields, body: lines[(end + 1)...].joined(separator: "\n"))
    }

    static func unquote(_ value: String) -> String {
        guard value.count >= 2, let first = value.first, first == value.last, first == "\"" || first == "'" else { return value }
        let inner = String(value.dropFirst().dropLast())
        return first == "'" ? inner.replacingOccurrences(of: "''", with: "'") : inner.replacingOccurrences(of: "\\\"", with: "\"")
    }
}

// MARK: - Completion state

/// Suggestions for the token being typed at the end of a draft. The draft is all the box exposes
/// (SwiftUI's TextField has no caret API), so completion works on its trailing token:
/// `/…` only as the whole draft, like the CLIs; `$…` as the last word, for Codex skill mentions.
public struct CommandCompletion: Equatable, Sendable {
    public var commands: [SlashCommand] = []
    public private(set) var suggestions: [SlashCommand] = []
    public private(set) var selection = 0
    /// Esc hides suggestions until the draft changes.
    private var dismissedDraft: String?

    public init(commands: [SlashCommand] = []) {
        self.commands = commands
    }

    public var isActive: Bool { !suggestions.isEmpty }

    public var selected: SlashCommand? {
        suggestions.indices.contains(selection) ? suggestions[selection] : nil
    }

    public mutating func update(draft: String) {
        if dismissedDraft != nil, dismissedDraft != draft { dismissedDraft = nil }
        guard dismissedDraft == nil, let token = Self.token(in: draft, triggers: Set(commands.map(\.trigger))) else {
            suggestions = []
            selection = 0
            return
        }
        let previous = selected?.id
        suggestions = SlashCommandCatalog.matches(commands.filter { $0.trigger == token.trigger }, query: token.query)
        selection = suggestions.firstIndex { $0.id == previous } ?? 0
    }

    /// Wraps around, like the CLI menus.
    public mutating func move(_ delta: Int) {
        guard !suggestions.isEmpty else { return }
        selection = ((selection + delta) % suggestions.count + suggestions.count) % suggestions.count
    }

    public mutating func dismiss(draft: String) {
        dismissedDraft = draft
        suggestions = []
        selection = 0
    }

    /// The draft with its trailing token replaced by the command and a space; nil without a selection.
    public func complete(_ draft: String, with command: SlashCommand? = nil) -> String? {
        guard let command = command ?? selected,
              let token = Self.token(in: draft, triggers: [command.trigger]) else { return nil }
        return String(draft[..<token.start]) + command.token + " "
    }

    /// The trailing token already names the selected command in full.
    public func isExact(_ draft: String) -> Bool {
        guard let selected, let token = Self.token(in: draft, triggers: [selected.trigger]) else { return false }
        return token.query == selected.name
    }

    struct Token: Equatable {
        var trigger: Character
        var query: String
        var start: String.Index
    }

    static func token(in draft: String, triggers: Set<Character>) -> Token? {
        guard let last = draft.last, !last.isWhitespace else { return nil }
        let start = draft.lastIndex(where: \.isWhitespace).map(draft.index(after:)) ?? draft.startIndex
        let word = draft[start...]
        guard let trigger = word.first, triggers.contains(trigger) else { return nil }
        switch trigger {
        case "/" where start == draft.startIndex, "$": // `/` only as the whole draft; `$` as any word
            return Token(trigger: trigger, query: String(word.dropFirst()), start: start)
        default:
            return nil
        }
    }
}
