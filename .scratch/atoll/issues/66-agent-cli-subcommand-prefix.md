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

**Status:** needs-triage
