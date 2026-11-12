import Foundation
import Testing
@testable import AtollCore

/// A throwaway directory tree: `write("a/b.md", "…")` creates parents as needed.
final class TempTree {
    let root: String

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("atoll-cmd-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(atPath: root) }

    func path(_ relative: String) -> String { (root as NSString).appendingPathComponent(relative) }

    func write(_ relative: String, _ text: String) throws {
        let full = path(relative)
        try FileManager.default.createDirectory(atPath: (full as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try text.write(toFile: full, atomically: true, encoding: .utf8)
    }

    func mkdir(_ relative: String) throws {
        try FileManager.default.createDirectory(atPath: path(relative), withIntermediateDirectories: true)
    }
}

private func skill(_ fields: String, body: String = "# Title\n") -> String {
    "---\n\(fields)\n---\n\(body)"
}

@Suite("Slash commands: frontmatter")
struct FrontmatterTests {
    @Test("plain, quoted and block values")
    func values() {
        let doc = Frontmatter.parse("""
        ---
        name: commit
        description: "Make a commit: conventional"
        argument-hint: '[it''s optional]'
        folded: >
          first line
          second line
        literal: |-
          a
          b
        list:
          - x
        ---
        # Body
        """)
        #expect(doc.fields["name"] == "commit")
        #expect(doc.fields["description"] == "Make a commit: conventional")
        #expect(doc.fields["argument-hint"] == "[it's optional]")
        #expect(doc.fields["folded"] == "first line second line")
        #expect(doc.fields["literal"] == "a\nb")
        #expect(doc.body.contains("# Body"))
    }

    @Test("plain value continued on indented lines")
    func continuation() {
        let doc = Frontmatter.parse("---\ndescription: one\n  two\nname: x\n---\n")
        #expect(doc.fields["description"] == "one two")
        #expect(doc.fields["name"] == "x")
    }

    @Test("no frontmatter → everything is body; fallback is the first non-empty line")
    func noFrontmatter() {
        let doc = Frontmatter.parse("\n\n## Deploy the app\nmore")
        #expect(doc.fields.isEmpty)
        #expect(doc.firstBodyLine == "Deploy the app")
    }
}

@Suite("Slash commands: catalog")
struct SlashCommandCatalogTests {
    @Test("Claude Code: personal skills and commands, frontmatter name, hidden skills, fallback description")
    func personal() throws {
        let home = try TempTree()
        try home.write(".claude/skills/commit/SKILL.md", skill("name: commit\ndescription: Make a commit\nargument-hint: <type>"))
        try home.write(".claude/skills/dir-name/SKILL.md", skill("name: renamed\ndescription: d"))
        try home.write(".claude/skills/no-name/SKILL.md", skill("description: d"))
        try home.write(".claude/skills/internal/SKILL.md", skill("name: internal\ndescription: d\nuser-invocable: false"))
        try home.write(".claude/skills/no-skill-file/README.md", "x")
        try home.write(".claude/commands/deploy.md", "Deploy the app\n")
        try home.write(".claude/commands/frontend/component.md", skill("description: Make a component"))

        let commands = SlashCommandCatalog.load(tool: .claudeCode, cwd: nil, home: home.root)
        let personal = commands.filter { $0.source == .personal }
        #expect(personal.map(\.token) == ["/commit", "/renamed", "/no-name", "/deploy", "/frontend:component"])
        #expect(personal[0].description == "Make a commit")
        #expect(personal[0].argumentHint == "<type>")
        #expect(personal[3].description == "Deploy the app")
        #expect(commands.contains { $0.token == "/compact" && $0.source == .builtIn })
    }

    @Test("project levels from cwd up to the repo root, not beyond")
    func projectLevels() throws {
        let home = try TempTree()
        try home.mkdir("work/repo/.git")
        try home.write("work/.claude/skills/outside/SKILL.md", skill("description: d"))
        try home.write("work/repo/.claude/skills/root-skill/SKILL.md", skill("description: d"))
        try home.write("work/repo/packages/app/.claude/commands/local.md", "Local\n")

        let commands = SlashCommandCatalog.load(tool: .claudeCode, cwd: home.path("work/repo/packages/app"), home: home.root)
        let project = commands.filter { $0.source == .project }.map(\.token)
        #expect(project == ["/local", "/root-skill"])
    }

    @Test("outside a repo only cwd itself; cwd = home adds no project level")
    func projectDirectories() throws {
        let home = try TempTree()
        try home.mkdir("a/b")
        #expect(SlashCommandCatalog.projectDirectories(from: home.path("a/b"), home: home.root) == [home.path("a/b")])
        #expect(SlashCommandCatalog.projectDirectories(from: home.root, home: home.root).isEmpty)
        #expect(SlashCommandCatalog.projectDirectories(from: nil, home: home.root).isEmpty)
    }

    @Test("skill beats a command of the same name; personal beats project")
    func precedence() throws {
        let home = try TempTree()
        try home.mkdir("repo/.git")
        try home.write(".claude/skills/ship/SKILL.md", skill("description: skill"))
        try home.write(".claude/commands/ship.md", skill("description: command"))
        try home.write("repo/.claude/skills/ship/SKILL.md", skill("description: project"))

        let ship = SlashCommandCatalog.load(tool: .claudeCode, cwd: home.path("repo"), home: home.root).filter { $0.name == "ship" }
        #expect(ship.count == 1)
        #expect(ship.first?.description == "skill")
    }

    @Test("enabled plugins only, from their installPath, namespaced by plugin name")
    func plugins() throws {
        let home = try TempTree()
        try home.mkdir("repo/.git")
        let on = home.path("cache/on/1.0"), off = home.path("cache/off/1.0"), proj = home.path("cache/proj/1.0")
        try home.write("cache/on/1.0/skills/review/SKILL.md", skill("name: fancy\ndescription: Review"))
        try home.write("cache/on/1.0/commands/dev.md", skill("description: Dev\nargument-hint: <task>"))
        try home.write("cache/on/0.9/skills/old/SKILL.md", skill("description: stale version"))
        try home.write("cache/off/1.0/skills/hidden/SKILL.md", skill("description: d"))
        try home.write("cache/proj/1.0/skills/scoped/SKILL.md", skill("description: d"))
        try home.write(".claude/plugins/installed_plugins.json", """
        {"version": 2, "plugins": {
          "on@market": [{"scope": "user", "installPath": "\(on)"}],
          "off@market": [{"scope": "user", "installPath": "\(off)"}],
          "proj@market": [{"scope": "project", "projectPath": "\(home.path("repo"))", "installPath": "\(proj)"}]
        }}
        """)
        try home.write(".claude/settings.json", #"{"enabledPlugins": {"on@market": true, "off@market": false}}"#)
        try home.write("repo/.claude/settings.json", #"{"enabledPlugins": {"proj@market": true}}"#)

        let outside = SlashCommandCatalog.load(tool: .claudeCode, cwd: nil, home: home.root).filter { if case .plugin = $0.source { true } else { false } }
        #expect(outside.map(\.token) == ["/on:fancy", "/on:dev"])
        #expect(outside[1].argumentHint == "<task>")

        let inRepo = SlashCommandCatalog.load(tool: .claudeCode, cwd: home.path("repo"), home: home.root).map(\.token)
        #expect(inRepo.contains("/proj:scoped"))
        #expect(!inRepo.contains("/off:hidden"))
    }

    @Test("plugin manifest paths: skill dirs, skill collections and command files, plus the defaults")
    func manifestPaths() throws {
        let home = try TempTree()
        let path = home.path("cache/mp/1.0")
        try home.write("cache/mp/1.0/.claude-plugin/plugin.json", """
        {"name": "mp", "skills": ["./skills/engineering/tdd", "./extra"], "commands": "./cmds/go.md"}
        """)
        try home.write("cache/mp/1.0/skills/engineering/tdd/SKILL.md", skill("name: tdd\ndescription: d"))
        try home.write("cache/mp/1.0/skills/engineering/unlisted/SKILL.md", skill("name: unlisted\ndescription: d"))
        try home.write("cache/mp/1.0/skills/top/SKILL.md", skill("name: top\ndescription: d"))
        try home.write("cache/mp/1.0/extra/one/SKILL.md", skill("name: one\ndescription: d"))
        try home.write("cache/mp/1.0/cmds/go.md", "Go\n")
        try home.write("cache/mp/1.0/cmds/other.md", "Other\n")
        try home.write("cache/mp/1.0/commands/ignored.md", "Default dir is replaced by the manifest\n")

        let tokens = SlashCommandCatalog.pluginCommands(.init(name: "mp", path: path)).map(\.token)
        #expect(tokens == ["/mp:top", "/mp:tdd", "/mp:one", "/mp:go"])
    }

    @Test("plugin manifest commands as a name → source/content map")
    func manifestCommandMap() throws {
        let home = try TempTree()
        try home.write("p/.claude-plugin/plugin.json", """
        {"name": "dt", "commands": {
          "status": {"source": "./commands/status.md", "argumentHint": "[env]"},
          "about": {"content": "Explain this plugin.", "description": "Describe it"}
        }}
        """)
        try home.write("p/commands/status.md", skill("description: Show status"))
        try home.write("p/commands/unlisted.md", "x\n")

        let commands = SlashCommandCatalog.pluginCommands(.init(name: "dt", path: home.path("p")))
        #expect(commands.map(\.token) == ["/dt:about", "/dt:status"])
        #expect(commands[0].description == "Describe it")
        #expect(commands[1].description == "Show status")
        #expect(commands[1].argumentHint == "[env]")
    }

    @Test("built-in aliases are listed, so a fully typed alias matches exactly")
    func aliases() {
        var c = CommandCompletion(commands: SlashCommandCatalog.claudeBuiltIns + [
            SlashCommand(name: "tpi-frontend-workflow:review", source: .plugin("tpi-frontend-workflow")),
        ])
        c.update(draft: "/review")
        #expect(c.selected?.name == "review")
        #expect(c.isExact("/review"))
    }

    @Test("Codex: $ skills from ~/.agents, ~/.codex and the repo; / built-ins")
    func codex() throws {
        let home = try TempTree()
        try home.mkdir("repo/.git")
        try home.write(".agents/skills/herdr/SKILL.md", skill("name: herdr\ndescription: d"))
        try home.write(".codex/skills/commit/SKILL.md", skill("name: commit\ndescription: d"))
        try home.write(".codex/skills/.system/imagegen/SKILL.md", skill("name: imagegen\ndescription: d"))
        try home.write("repo/.agents/skills/local/SKILL.md", skill("name: local\ndescription: d"))
        try home.write(".claude/skills/claude-only/SKILL.md", skill("description: d"))

        let commands = SlashCommandCatalog.load(tool: .codex, cwd: home.path("repo"), home: home.root)
        let skills = commands.filter { $0.trigger == "$" }
        #expect(skills.map(\.token) == ["$herdr", "$commit", "$local", "$imagegen"])
        #expect(skills.last?.source == .builtIn)
        #expect(commands.contains { $0.token == "/model" })
        #expect(!commands.contains { $0.name == "claude-only" })
    }

    @Test("generic agents get nothing")
    func generic() throws {
        let home = try TempTree()
        try home.write(".claude/skills/x/SKILL.md", skill("description: d"))
        #expect(SlashCommandCatalog.load(tool: .generic, cwd: nil, home: home.root).isEmpty)
    }
}

@Suite("Slash commands: matching")
struct SlashCommandMatchingTests {
    let commands = [
        SlashCommand(name: "compact", source: .builtIn),
        SlashCommand(name: "commit", source: .personal),
        SlashCommand(name: "code-review", source: .personal),
        SlashCommand(name: "tpi-frontend-workflow:review", source: .plugin("tpi-frontend-workflow")),
        SlashCommand(name: "mattpocock-skills:code-review", source: .plugin("mattpocock-skills")),
        SlashCommand(name: "preview-deck", source: .project),
    ]

    @Test("name prefix, then last segment, then any word, then anywhere")
    func ranking() {
        #expect(SlashCommandCatalog.matches(commands, query: "rev").map(\.name) == [
            "tpi-frontend-workflow:review",
            "code-review", "mattpocock-skills:code-review",
            "preview-deck",
        ])
    }

    @Test("ties: personal before built-in; case-insensitive")
    func ties() {
        #expect(SlashCommandCatalog.matches(commands, query: "CO").map(\.name).prefix(3) == ["code-review", "commit", "compact"])
    }

    @Test("empty query lists everything")
    func empty() {
        #expect(SlashCommandCatalog.matches(commands, query: "").count == commands.count)
    }
}

@Suite("Slash commands: completion")
struct CommandCompletionTests {
    let commands = [
        SlashCommand(name: "commit", source: .personal),
        SlashCommand(name: "compact", source: .builtIn),
        SlashCommand(name: "clear", source: .builtIn),
        SlashCommand(trigger: "$", name: "imagegen", source: .builtIn),
    ]

    @Test("/ only as the whole draft; $ as the last word; nothing after a space")
    func triggers() {
        var c = CommandCompletion(commands: commands)
        c.update(draft: "/co")
        #expect(c.suggestions.map(\.name) == ["commit", "compact"])
        c.update(draft: "please /co")
        #expect(!c.isActive)
        c.update(draft: "draw it with $im")
        #expect(c.suggestions.map(\.token) == ["$imagegen"])
        c.update(draft: "/commit ")
        #expect(!c.isActive)
        c.update(draft: "")
        #expect(!c.isActive)
        c.update(draft: "/zzz")
        #expect(!c.isActive)
    }

    @Test("complete replaces the trailing token and adds a space")
    func complete() {
        var c = CommandCompletion(commands: commands)
        c.update(draft: "/co")
        c.move(1)
        #expect(c.complete("/co") == "/compact ")
        c.update(draft: "use $i")
        #expect(c.complete("use $i") == "use $imagegen ")
        #expect(c.complete("use $i", with: commands[0]) == nil) // a `/` command can't replace a `$` word
    }

    @Test("selection wraps and survives narrowing when still listed")
    func selection() {
        var c = CommandCompletion(commands: commands)
        c.update(draft: "/c")
        #expect(c.selected?.name == "commit")
        c.move(-1)
        #expect(c.selected?.name == "compact")
        c.update(draft: "/com")
        #expect(c.selected?.name == "compact")
        c.move(1)
        #expect(c.selected?.name == "commit")
    }

    @Test("Esc hides suggestions until the draft changes")
    func dismiss() {
        var c = CommandCompletion(commands: commands)
        c.update(draft: "/c")
        c.dismiss(draft: "/c")
        #expect(!c.isActive)
        c.update(draft: "/c")
        #expect(!c.isActive)
        c.update(draft: "/co")
        #expect(c.isActive)
    }

    @Test("exact: the draft already names the selected command")
    func exact() {
        var c = CommandCompletion(commands: commands)
        c.update(draft: "/commit")
        #expect(c.isExact("/commit"))
        c.update(draft: "/comm")
        #expect(!c.isExact("/comm"))
    }
}
