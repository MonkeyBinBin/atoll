# 67: 在 Settings 自訂啟動選單的 agent CLI

**What to build:** 啟動選單只偵測寫死在 `AgentCLI.catalog` 的 CLI，使用者裝了未收錄的 CLI（例如 PR #14 之前的 Antigravity CLI）就不會出現，每支援一個 CLI 都要改 code、發版。讓使用者在 Settings 自己加 CLI：

- command、選單標題
- 怎麼帶首個 prompt：最後一個參數 / 指定 flag / 不支援（對應 `TaskPassing`），以及 #66 的子指令前綴
- 選填的 OSC 7501 app word（`appWords`），讓「Launch in new worktree」能預選同一工具
- 選填的 `--help` 特徵字串（`helpSignature`），給名稱通用的 command

自訂項目與 catalog 一起走 `AgentCLIDetector` 偵測，存在 UserDefaults（`local.atoll`）。command 與 catalog 重複時以哪邊為準要決定。

現有的替代方式是寫 herdr-core template（啟動選單會列 `hc templates`），但 template 沒有 `taskPassing`，task 一律接在最後。

**Blocked by:** 66

**Status:** resolved

## Comments

- 2026-11-23（agent）：command 與 catalog 重複時，使用者決定**自訂覆蓋內建**（原位取代，option id 仍是 `builtin:<command>`，舊 recipe／preset 照樣對得上）。實作：
  - `AgentCLI`、`TaskPassing` 改為 `Codable`，存在 `customAgentCLIs`（JSON）
  - `AgentCLI.isValidCommand`：command 未經引號放進偵測 script，限 `[A-Za-z0-9][A-Za-z0-9._+-]*`；其他欄位只進 argv 或 Swift 比對
  - `AgentCLI.merged(custom:)`：覆蓋同名、追加其餘，略過不合法與重複
  - `AgentCLIDetector.update(clis:)`：Settings 變更時換清單，`lastKnown` 與進行中的偵測結果都依 command 對應到新定義
  - `AgentCLIDraft`：Settings 編輯器的字串欄位與驗證，`IslandModel.agentCLIs` 給 `matching(app:in:)` 與啟動表單使用
  - Settings 新增「Agent CLIs」：列表、Add／Edit sheet（task 方式：Last argument／After a flag／After arguments／Not supported）、與內建同名時標 `replaces built-in`
- 2026-11-23（agent）：依 code review 修正。`claude`／`codex` 列為保留字（option id 會與內建重複），編輯器擋下、`merged` 略過；`matching(app:in:)` 先找整份清單的完全相符，再退回 `<name>-` 前綴，避免 `opencode-dev` 被 OpenCode 搶走；加入進行中偵測的 refresh 也對應到新定義；新定義要求不同的 help signature 時不沿用舊偵測結果；啟動表單以 command 比對，選項一律用 `model.agentCLIs` 的現行定義；儲存資料逐筆解碼（`AgentCLI.decodeList`），壞一筆只丟那一筆。輸出版面解析起初只認 catalog，第二輪 review 改為傳入合併清單（見下）。
- 2026-11-23（agent）：第二輪 review。`OutputFilter` 的 `messages`／`activityFingerprint`／`genericMessages`／`isAntigravity` 加 `clis` 參數，`AgentStore.agentCLIs` 與 `AgentPanelView` 傳入合併清單，Settings 的 `opencode-dev` 不再以 OpenCode 版面解析（前一則低估了影響）。command 比對與保留字不分大小寫；Settings 與 catalog CLI 的 `LaunchOption.tool` 一律 `.generic`（`claude-yolo` 不再被當成 Claude Code）。偵測器：`update(clis:version:)` 丟棄晚到的舊版本更新；偵測中途清單有變時，結束前以新清單再跑一次，新增的 CLI 不會被漏掉。啟動表單開著時被刪的 CLI 沿用舊定義，不會默默換成 Claude Code。
- 2026-11-23（agent）：第三輪 review。command 存檔時轉小寫，`merged` 也不分大小寫比對（`OpenCode` 會覆蓋 `opencode` 而不是並列）。新增 CLI 時輸入內建 command 且 title 還空著，自動帶入內建定義（`AgentCLIDraft.adoptCatalogEntry`），覆蓋時不會丟掉 `antigravity` app word 或 help signature。偵測器結束時「確認清單沒變」與「清除 running、存結果」在同一個 actor 方法完成，不再有 update 插進中間而被漏掉；`update(redetect: true)` 在沒有偵測進行時立即重新偵測，remap 改變已偵測清單時也通知存檔。編輯器無法顯示的 `.verbatim` 在 picker 沒動時保留。列表 id 改用 command。
- 2026-11-23（agent）：第四輪 review。上一輪的「輸入內建 command 自動帶入定義」在每次按鍵觸發，打 `pixel-agent` 經過 `pi` 時會黏上 Pi 的定義；改為 `AgentCLIDraft.followCommand()`，記住來源 command，打過頭就清回空白。`claude`／`codex` 開頭的 command 一律保留（`AgentTool.from(app:)` 以前綴判定，`claude-yolo` 會被追蹤成 Claude Code，與啟動不一致）。撤回存檔轉小寫，command 照原樣保存（區分大小寫的磁碟要用），只有去重、保留字、覆蓋時不分大小寫。讀取時去掉重複 command；Settings 變更通知與 `store.agentCLIs` 同步移出 demo 判斷；編輯器動過欄位才顯示錯誤。
- 2026-11-23（agent）：第五輪 review。覆蓋內建時保留 catalog 的 command 拼法（`OpenCode` 覆蓋後仍是 `opencode`），option id 與版面判斷不變。`followCommand()` 帶入後若改過其他欄位，command 再改就停止跟隨、保留修改。編輯器在 command 是內建、而 app words／help signature 少了內建有的值時顯示提示（不自動合併）。讀取時丟掉不合法或保留的 command。啟動表單 `options` 套用與偵測器相同的 signature 規則；`takeRefreshed` 找選中項目時也查 `installed`（Settings 刪掉的 CLI 不再變成 Claude Code）。review 指 `isValidCommand` 的 `$` 會放行結尾換行，實測 `"aider\n"` 不相符，未改正則，只讓 `build()` 一併去掉換行。
- 2026-11-23（agent）：第六輪 review。啟動表單：Settings 改了選中 CLI 的 help signature（或移除帶 signature 的覆蓋）時沿用偵測當時的定義，不再消失變成 Claude Code；表單開著時清單變動會重新偵測並更新。`matching(app:in:)` 依序比 command、app word、前綴，各自跨整份清單（自訂 `antigravity` 不再被 agy 搶走）。`followCommand()` 只在 command 以外的欄位都是預設值時帶入。`detectedAgentCLIs` 存檔時讀偵測器當下的 `lastKnown`，不再受 Task 執行順序影響。demo 模式啟動時同步一次清單。`isValidCommand` 排除 shell 關鍵字與 builtin（`command -v` 必定找得到）。比對字串提示不分大小寫。
- 2026-11-23（agent）：第七輪 review。上一輪讓 command 優先於 app word，反而讓自訂 `cursor`／`antigravity` 搶走內建 CLI 的 agent；改為不允許：自訂 command 不能等於內建 CLI 的 app word（`AgentCLI.catalogOwningAppWord`），編輯器顯示原因，`merged` 與讀取時略過。`shellWords` 補上 zsh／fish builtin（`r`、`print`、`setopt`、`abbr` 等）。「wasn't found」提示不重複；demo 模式啟動同步帶版本號；重複檢查去掉換行；picker 切換過就不再保留 `.verbatim`。
- 2026-11-23（agent）：第八輪 review。前幾輪反覆調整比對順序（command 優先、app word 優先、前綴），每次都讓內建或自訂其中一邊被搶。改為根本規則：自訂 command 若會被任何內建 CLI 對到（app word 或 `<command>-` 前綴，`AgentCLI.catalogClaiming`），一律拒絕，覆蓋同一筆內建除外；內建與自訂名稱不再重疊，比對順序不再影響結果。代價是 `opencode-dev`、`copilot-cli` 這類以內建名稱開頭的 wrapper 不能自訂。另：帶入內建定義後改名時，未改過的 app word／help signature 一併清掉；補 zsh／bash builtin；讀不懂或被規則擋下的儲存項目保留原始 JSON，存檔時寫回（`decodeStored`／`encodeStored`）；未變更的 Save 不寫入、不重新偵測；`IslandModel.agentCLIs` 改為存起來的值。
