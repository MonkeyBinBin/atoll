# 66: 需要子指令才能帶首個 prompt 的 CLI 無法加入啟動選單

**What to build:** `AgentCLI` 只有 `command` 一個欄位，launch argv 是 `[command] + taskPassing`。有些 CLI 要先接子指令才能開互動 session 並帶首個 prompt，現在無法表達，所以 PR #14 沒有收錄：

| CLI | command | 互動 + 首個 prompt | 要避開 | 來源 |
|---|---|---|---|---|
| Kiro CLI | `kiro-cli` | `kiro-cli chat "<task>"`（不帶 task 時 `kiro-cli` 預設就是 `chat`） | `--no-interactive` | kiro.dev/docs/reference/cli-commands/ |
| Hermes | `hermes` | `hermes chat -q "<task>"` | `--oneshot`、`-z`、`-Q`；非 TTY 會變 one-shot；`hermes-agent` binary 是 one-shot | hermes-agent.nousresearch.com/docs/reference/cli-commands |
| Goose | `goose` | `goose run -s -t "<task>"`（`-s` = 處理完首個輸入後留在互動模式） | 少了 `-s` 會直接結束 | goose-docs.ai/docs/guides/goose-cli-commands |

做法方向：`AgentCLI` 加 argv 前綴（例如 `arguments: [String]`，偵測仍只看 `command`）。不帶 task 時的 argv 要分開考慮：Goose 的 `goose run -s` 沒有 `-t` 可能不合法，不帶 task 時應該跑 bare `goose`（`goose session`）。

三者的 OSC 7501 app word 都未實測：herdr-app `programs.json` 有 `kiro`（含 `kiro-cli`）、`hermes`、`goose`。本機都沒有安裝，flag 只對照官方文件（2026-11-23 查）。

**Blocked by:** —

**Status:** claimed

## Comments

- 2026-11-23（agent）：沒有另加 `AgentCLI.arguments`，改在 `TaskPassing` 新增 `.arguments(withTask:withoutTask:)`：herdr 把 task 接在 argv 最後，有無 task 的參數本來就不同（Goose 不帶 task 要跑 `goose session`），放在 task passing 一處表達。catalog 加入：
  - `kiro-cli`：有 task `chat <task>`，沒有 task 跑 bare `kiro-cli`（預設即 `chat`）；`appWords: ["kiro"]`
  - `hermes`：有 task `chat -q <task>`，沒有 task `chat`。原始碼 `hermes_cli/_parser.py` 的 `-q` 說明：真 TTY 上會 seed 互動 session，`--oneshot`／`-Q`／非 TTY 才答完就結束；0.21 之前 `-q` 是 one-shot。`hermes` 也是 Hermes JS 引擎的指令，加 `helpSignature: "Hermes Agent"`（頂層 parser description）
  - `goose`：有 task `run -s -t <task>`，沒有 task `session`。原始碼 `crates/goose-cli/src/cli.rs` 確認 `-t/--text`、`-s/--interactive`。`goose` 也是 pressly 的 DB migration 工具，加 `helpSignature: "interactive chat sessions"`（`session` 子指令說明）
  - 三者本機都沒裝，未實際啟動；app word 只依 herdr-app `programs.json`
