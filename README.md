# Atoll

在 macOS 螢幕頂部（與瀏海融合）顯示像素風「動態島」，即時呈現本機所有 AI coding agent（Claude Code、Codex）的狀態，並能直接回覆、中斷或切回原本的終端機。

![動態島收合態](docs/screenshots/island.png)

同時跑多個 agent 時，不用逐一切視窗查看誰在工作、誰在等你回覆、誰出錯了：每個 agent 是站在自己小沙洲上的小機器人，需要注意的永遠釘在最顯眼的位置。

> 自用工具：ad-hoc 簽章、未 notarize，不對外發佈。

## 功能

- **監看**：每個 agent 一個角色，外觀代表工具、個體色在 session 內固定；動畫之外一律附圖示與文字（Working / Needs you / Done / Idle / Error / Exited / Unknown）。等待使用者與錯誤的 agent 釘在左翼，其餘依優先級排列。
- **環礁場景**：動態島背景是一片環礁，每個 agent 站在自己的沙洲上，海浪流動、偶爾有魚跳出水面；等待你或出錯的 agent 腳下水面會映出黃光／紅光。天空、海水與日月依本機時間從黎明、白天、黃昏變化到深夜。設定裡關掉 Decorations 即回到純黑。
- **清單**：點動態島空白處或按 `⌥⌘A` 展開，依「等待使用者 > 錯誤 > 狀態未知 > 執行中 > 完成／閒置」排序。`↑↓` 選擇、`Enter` 打開、`⌘1`–`⌘9` 直接跳、`Esc` 逐層返回。
- **互動面板**：看近期終端機輸出、傳送訊息、回答 `blocked: question`、用按鍵排回應 permission prompt、中斷目前任務（1.5 秒內二次確認），或一鍵切回原終端機接手。送出狀態明確區分 Delivered / Agent started / Sent · unconfirmed / Failed，永不自動重送。回應完一個等待中的 agent、它確實離開等待後，面板自動切到下一個等最久的 agent（輸入框有未送出文字時不切），全部處理完顯示 All clear；標題列顯示還有幾個在等，`⌘]` 手動跳下一個。可在設定關閉自動切換。
- **啟動**：點動態島上的「＋」（或清單底部的 Launch agent），透過 Herdr 開新的 Claude Code、Codex 或 herdr-core template agent。
- **對話泡泡**：agent 停下來（Done／Idle／Exited）、等待你或出錯時，該角色下方冒出約 5 秒的狀態泡泡；一次一個，等待與錯誤優先，點泡泡直接打開面板。可在設定關閉。
- **通知**：agent 等待你或出錯時發 macOS 通知，內容只有「工具 · 專案名」；`⌃⌥⌘A` 直接打開最早開始等待的 agent。等待超過設定時間（預設 5 分鐘，可關閉）仍沒處理會再提醒一次，泡泡也再冒一次。面板上的鈴鐺可設定「這次跑完時通知我」，通知一次後自動關閉。
- **誠實的狀態**：來源斷線或超過 heartbeat 期限時，動態島轉灰並標示「狀態未知」，不從畫面文字猜測狀態。
- **隱私**：只和本機的 herdr-core、herdr CLI、cmux 溝通；近期輸出只在面板開著時留在記憶體。

| 清單 | 互動面板 |
| --- | --- |
| ![Agent 清單](docs/screenshots/list.png) | ![互動面板](docs/screenshots/panel.png) |

| 啟動 agent | 設定 |
| --- | --- |
| ![啟動表單](docs/screenshots/launch.png) | ![設定視窗](docs/screenshots/settings.png) |

| 對話泡泡 | 一天的環礁（黎明 → 白天 → 正午 → 黃昏 → 深夜） |
| --- | --- |
| ![角色下方的狀態泡泡](docs/screenshots/bubble.png) | ![依時間變化的背景](docs/screenshots/daycycle.png) |

角色是原生 16×16 的像素小機器人（Claude Code／Codex／通用三種頭型），每個狀態有對應動畫：

![角色與狀態動畫](docs/screenshots/characters.png)

## 支援的 agent 來源

| 來源 | 讀取方式 |
| --- | --- |
| herdr-core（Herdr app） | 直接連 core 的 Unix socket（JSON-RPC 2.0），訂閱事件串流 |
| herdr CLI／TUI | `~/.config/herdr/herdr.sock`，`agent.list` 輪詢＋pane 事件 |
| cmux | `cmux events` 的 `agent.hook.*` 事件；cmux 沒開時不呼叫任何 cmux 指令 |
| 其他終端機（Ghostty、iTerm、VS Code…） | 選用：source `scripts/shell/atoll.zsh`，把 `claude`／`codex` 改經 `hc run` 執行 |

前三者不需要改任何 shell 設定。在其他終端機使用時，於 `~/.zshrc` 加入：

```zsh
source /path/to/atoll/scripts/shell/atoll.zsh
```

來源 app 會自動偵測；偵測錯誤時可用 `export ATOLL_ORIGIN=<bundle id>` 覆寫。

## 需求

- macOS 15 以上（Apple Silicon 驗證過）
- Swift 6 toolchain（Xcode 16 以上或 Command Line Tools）
- 至少一個 agent 來源：herdr-core（驗證版本 `hc` 0.1.19 ＋ Herdr app 0.1.14）、herdr CLI 0.9.x 或 cmux
- 啟動 agent 與「Open in Herdr」需要 Herdr app 執行中

## 建置與執行

```sh
./scripts/build-app.sh          # 產出 build/Atoll.app（release、ad-hoc 簽章）
open build/Atoll.app
```

Atoll 是 menu bar app（`LSUIElement`），沒有 Dock 圖示；從 menu bar icon 開關動態島、打開設定或結束。

開發時可用 debug hook 重建並重啟（會把畫面渲染到 `$ATOLL_DEBUG_DIR/*.png`，並讀取 `$ATOLL_DEBUG_DIR/cmd` 的指令，見 `Sources/Atoll/DebugHook.swift`）：

```sh
ATOLL_DEBUG_DIR=/tmp/atoll-debug ./scripts/dev-run.sh
```

## 測試

```sh
swift test                                        # AtollCore 單元測試（fake client，不需任何後端）
HERDR_CONTRACT=1 swift test --filter Contract     # 對本機真實 herdr-core 的契約測試
```

契約測試預設不跑，只做唯讀操作與自己建立、自己清除的測試 terminal。herdr-core 協定仍是 preview，升級後應重跑。

## 專案結構

```
Sources/
  AtollCore/   領域核心：各來源 adapter（CoreRPC／HerdrCLI／Cmux）、AgentStore（狀態對映、排序、送出／啟動狀態機）、通知規則
  Atoll/       App：動態島 NSPanel、SwiftUI 視圖、SpritePlayer、menu bar、設定、全域快捷鍵
    Resources/Sprites/   sprite sheet（PNG + Aseprite 風格 JSON）
Tests/AtollCoreTests/    Swift Testing，以 fake HerdrClient 驗證 AgentStore 行為
scripts/                 build-app.sh、dev-run.sh、shell 包裝、占位 sprite 產生器
.scratch/atoll/          spec、issues（ticket 01–24）、美術探索與定稿
```

所有業務邏輯都在 `AtollCore`（不依賴 AppKit／SwiftUI）；UI 只讀 `AgentStore` 的狀態並轉發使用者意圖。

## 文件

- [`spec.md`](.scratch/atoll/spec.md)：P0 規格、狀態對映、協定細節與已驗證事實
- [`issues/`](.scratch/atoll/issues/)：實作 tickets（目前 01–24 除 17 pixelfx 特效層外皆已完成）
- [`art/`](.scratch/atoll/art/)：風格探索 board 與 B / Toy Chunky 定稿美術
