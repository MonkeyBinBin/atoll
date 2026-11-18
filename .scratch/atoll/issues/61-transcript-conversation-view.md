# 61: 輸出 panel 改讀 session transcript，顯示完整對話

**What to build:** 輸出 panel 目前只顯示一段對話。內容是從終端機讀回來的畫面文字，有三層上限：
- 讀取最多 200 行：`AgentStore.timing.outputLines`，herdr 用 `pane.read` 的 `recent_unwrapped`，cmux 用 `read-screen --scrollback --lines 200`。
- 終端機 scrollback 本身就短，這是主因。2026-11-18 實測 cmux 裡的 Claude Code session：要 200 行只拿到 54 行，大約是一個畫面高，對話歷史大多不在 scrollback 裡。原因還不確定，可能是 Claude Code 會重繪，或用了 alternate screen。
- Messages 模式再拿掉輸入框、statusline 與裝飾列。agent 在 working 或等使用者回應時，部分 adapter 只回傳畫面（panel 標「Screen only」）。

另一個問題是顏色。Claude Code 在畫面上會拿掉 markdown 標記（反引號、`**`、`#`），cmux 又只給純文字，所以 `OutputStyling.heuristic` 只能從版面猜；herdr 雖然拿得到 ANSI 原色，範圍一樣受 scrollback 限制。

Claude Code 和 Codex 都把完整對話寫在本機的 JSONL transcript 裡，內容是原始 markdown：
- Claude Code：`~/.claude/projects/<cwd 把 / 換成 ->/<session-id>.jsonl`。`type` 為 `user` / `assistant` 的列帶 `message.content`，block 有 `text`、`thinking`、`tool_use`、`tool_result`；另外還有很多內部列（`attachment`、`api-request*`、`cost-state`…）。
- Codex：`~/.codex/sessions/YYYY/MM/DD/rollout-<時間>-<session-id>.jsonl`。`response_item` 的 payload 有 `message`、`reasoning`、`function_call` / `function_call_output`、`custom_tool_call`…，`event_msg` 有 `task_started` / `task_complete`。

兩種格式都不是公開 API，版本更新可能會變。

做法：panel 能對應到 agent 的 transcript 時，改用 transcript 顯示完整對話，並依 markdown 結構上色（標題、粗體、code block、清單、連結，tool 呼叫與輸出調暗）；對應不到、解析失敗或格式不認得時，退回現在的終端機輸出。

**Blocked by:** —

**Status:** resolved

- [x] 決定 agent → transcript 怎麼對應，結論寫在 Comments。已知線索：`cmux sessions list` 會給 session id、surface 與 cwd（Codex 另有 `codex_transcript=yes`）；herdr 的 `agent.list` 沒有 session id，可能要靠 cwd + 最近更新的檔案（同一個 cwd 有多個 session 時會撞），或靠 Claude Code hook 帶的 `session_id` / `transcript_path`
- [x] transcript 解析放在 AtollCore，Claude Code 與 Codex 各一個 parser，輸出統一的訊息結構（角色、文字、tool 呼叫 / 結果）；不認得的列略過，不 crash；用去識別化的 fixture 寫測試
- [x] panel 顯示 transcript 時依 markdown 上色，沿用 `StyledRun` / `TerminalPalette`；⌘F 搜尋、自動捲到底、Wrap 照常可用
- [x] 退回終端機輸出的時機明確：對應不到、檔案讀不到、解析結果是空的。panel 要標示目前顯示的是哪一種來源
- [x] 讀取成本可接受：transcript 可能數 MB，只解析尾端或增量讀取，不在每次 panel 重繪時重讀
- [x] 等使用者回應的對話框（permission、question）仍以終端機畫面為準，`WaitingPreview`、`PermissionChoices` 等 parser 不改讀 transcript
- [x] `make check` 通過；實機確認 cmux 與 herdr 裡的 Claude Code、Codex 各一個 session

**Out of scope:**
- OpenCode 與其他 generic agent 的 transcript
- 從 transcript 推斷 agent 狀態（狀態仍由各 adapter 提供）
- 在 panel 裡編輯、fork 或重播對話
- 把 transcript 內容送出本機，或寫進任何 log

## Comments

- 2026-11-18（agent）：起因是 `feat/output-colors`（輸出 panel 上色）實測時發現 panel 只顯示片段。那個 branch 已經讓 herdr 讀 ANSI 原色、cmux 依版面上色，但兩者都受終端機 scrollback 限制，所以另開這張 ticket 處理完整對話。
- 2026-11-18（agent）：對應方式定案：只走確定的連結，不用 cwd + 最近檔案猜（同一個 working tree 有兩個 agent 時會顯示到別人的對話）。來源依序：source 給的 transcript 路徑 → source 給的 session id → （僅 Claude Code）agent 程序 pid 的 `~/.claude/sessions/<pid>.json` 裡的 `sessionId`，且該檔的 `cwd` 必須等於 agent 的 cwd，避免 pid 被重用時讀到舊檔。各來源：cmux 以 hook 的 `session_id` 設 `atoll.session.id` label；herdr CLI 讀 `agent.list` 的 `agent_session`（`kind` 為 `id` / `path`，由 herdr 的 agent integration 回報，可能是 null）；herdr-core 用 `foreground.pid`。Codex 只有在 source 給 session id 時才找得到（`~/.codex/sessions/**/rollout-*-<id>.jsonl`），只有 pid 時退回終端機輸出。實測：這個 session（herdr-core、Claude Code）由 pid 檔對到正確的 transcript。未驗證：`/clear` 後 pid 檔的 `sessionId` 會不會更新——用 `hc send` 測試時 slash command 被包成訊息送給模型，沒有執行；若不更新，panel 會顯示同一個 agent `/clear` 前的對話，不會是別的 agent 的。herdr CLI 的 `agent_session` 只看過 schema，沒看過真實回應。
- 2026-11-18（agent）：實作：`Transcript.swift`（Claude Code / Codex parser，只讀白名單列：Claude 只讀非 meta、非 sidechain 的 `user` / `assistant`，Codex 只讀 `response_item`；thinking / reasoning、developer 訊息、注入的 context 與 system-reminder 等包裝都略過；tool 輸出只留 4 列）、`TranscriptLocator.swift`、`TranscriptReader.swift`（actor，增量讀取：每個 agent 記住檔案、offset、未完成的最後一行與項目；第一次只讀尾端 4 MB 並丟掉第一個不完整的行；最多 400 個項目；檔案換了或變短就重讀）、`TranscriptRendering.swift`（仿 Claude Code 畫面：`❯` / `⏺` / `⎿`；回覆的 markdown 去掉標記後上色）。adapter 的 `diff` 現在會在 label 改變時發 `.labels`（cmux `/clear` 換 session id），`.foreground` 也保留 pid。panel：勾選 Messages only、找得到 transcript、agent 不在 Needs you 時顯示 transcript 並標「Transcript」；取消勾選就是終端機畫面；Needs you 時顯示終端機畫面，因為對話框只在畫面上。agent 完成後 1.5 秒再讀一次，以防最後一則回覆還沒寫進檔案。turn 進行中只看得到已經完成的 block。
- 2026-11-18（agent）：測試：新增 `TranscriptTests`（parser、locator、reader、rendering、store 整合，資料全部合成）與 `OutputRenderingTests.transcriptWins`。`make check` 通過。實測這個 session 的 4 MB transcript：第一次讀取（背景）85 ms、無變化時重讀 0.05 ms、渲染 982 列 11 ms；debug 版打開 panel 截圖，transcript 正確顯示並標「Transcript」。尚未實機確認：cmux 與 herdr CLI 的 Claude Code、任何來源的 Codex。
- 2026-11-18（agent）：自我檢查後修正：（1）平行 tool 呼叫（近期 Claude transcript 有 513 處連續兩個 `tool_use`）的輸出原本都掛在最後一個呼叫下，改成依 id 配對（Claude `tool_use.id` ↔ `tool_use_id`，Codex `call_id`），各自放在自己的呼叫底下；（2）`<` 開頭的使用者訊息原本整則略過，會吃掉 `<hc>`、`<pasted_content>`、`<scheduled-task>` 等真正的訊息，改成只略過已知包裝（system-reminder、local-command-caveat、task-notification、command-message、user-prompt-submit-hook），`<hc from=…>…</hc>` 只顯示內文；Codex 只略過 environment_context、user_instructions、image 標記與 AGENTS.md；（3）略過 `isCompactSummary` 列；（4）完成後重讀改成「從 Working 轉出」就觸發，不限 Done（Codex 可能停在 Idle）；`LiveScheduler` 不需保留回傳的 handle 也會觸發；（5）pid 檔防重用改成比對 `startedAt` 與程序啟動時間（sysctl，實測相差 0.3–1.6 秒，容許 30 秒），讀不到啟動時間才比 cwd——agent 的 cwd 可能退回 terminal 的 cwd（herdr-core 的 `t7g` terminal 開在 dotfiles、claude 在 atoll）。實測 93.6 MB 的 transcript：只讀尾端 4 MB，120 個項目，73 ms；debug 版在 transcript 畫面確認 ⌘F（6 / 6、highlight、捲到符合處）、自動捲到底與 Wrap。排查時發現 17:14 起有一個帶 debug hook 的舊版 Atoll（`build/Atoll.app`，相對路徑啟動，先前的 kill 沒比對到）一直在跑，搶讀 debug 指令，期間的「Screen only」截圖是它拍的；已關閉。
- 2026-11-18（agent）：限制：每個 agent 最多 400 個項目、只讀尾端 4 MB；tool 輸出只留 4 列；turn 進行中只看得到已寫入的 block；Needs you 時顯示終端機畫面。尚待實機確認：cmux 的 Claude Code（cmux 目前沒開）、herdr CLI（server 沒開，`agent_session` 是否為 null 未知）、任何來源的 Codex、在開著 panel 的 session 裡 `/clear`（若 pid 檔不更新，panel 會停在舊對話，需改成退回終端機畫面）、從 Atoll reply 欄送出的訊息是否出現在 transcript。
- 2026-11-18（agent）：實機測試（debug 版 + debug hook 截圖）：cmux 的 Claude Code ✓、`/clear` 後重開 panel 只顯示新 session ✓、從 reply 欄送出的訊息（狀態沒變，靠輪詢）✓、cmux 的 Codex ✓。測試中發現並修正：（1）cmux 回報的 session id 不一定是工具自己的（它恢復的 session 回報 `cmux-…`），Claude 改成依序嘗試 source 的 id 與 pid 檔的 id；（2）Codex 沒有 pid 檔，改從 agent 程序開著的檔案（libproc）找 `~/.codex/sessions/` 下的 `rollout-*.jsonl`——Codex 執行期間會一直開著它，屬於確定的連結；（3）panel 只在狀態轉換時重讀，來源沒回報狀態時會卡住（cmux 恢復的 session 實測不回報），改成 panel 開著時每 2 秒增量讀一次 transcript，與終端機輸出各用一個 request 編號；未變時不更新 panel。`/clear` 確認會更新 pid 檔的 `sessionId`（`0d9e0320` → `a42ccb5b`），`startedAt` 不變。另外發現 cmux 既有行為：`/clear` 時舊 session 的 `SessionEnd` 先到，agent 短暫消失，開著的 panel 會被關回列表（與本 ticket 無關，未修）。herdr CLI 未測：對 herdr 還原出來的使用者 pane 打字被權限層擋下。
- 2026-11-18（agent）：PR #8 合併（`c750177`），之後再經四輪 review 修正：定位以程序自己的記錄為唯一候選（Claude pid 檔、Codex 開著的 rollout 檔）、只查 UUID 形式的 session id、讀不到超過 6 秒才退回畫面、顯示 transcript 時不讀終端機畫面、reader 在背景渲染並偵測檔案替換或原地改寫。
- 2026-11-18（使用者）：安裝後實測 herdr 裡的 agent，panel 顯示 transcript。至此 cmux 的 Claude Code、Codex 與 herdr 皆已實機確認。
