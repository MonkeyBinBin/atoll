# 48: 閒置時暫停或放慢動畫，降低常駐 CPU

**What to build:** Atoll 閒置（收合、沒有操作）時常駐約 5–6% CPU。`sample` 顯示 main thread 的工作幾乎都是 SwiftUI display cycle 重繪：環礁海浪 `TimelineView(.animation(minimumInterval: 0.2))` 持續 5 fps，且只看 `animationsEnabled`／Reduce Motion，螢幕睡眠、鎖定或動態島隱藏時照跑。

**Status:** resolved

- [x] 沒人看得到動態島時（螢幕睡眠、鎖定、切到其他使用者、動態島關閉、全螢幕隱藏）所有動畫停在靜止格
- [x] 收合且沒有 Needs you／Error 時，海浪降到 2 fps；展開或有人在等時維持 5 fps
- [x] 角色動畫與特效（celebrate／send）跟著同一個開關

**Out of scope:** hover card 與對話泡泡（各自的視窗、短暫顯示）；角色 sprite 的節奏（收合時已會 settle 到 1 Hz）。

## Comments

- 2026-11-13（agent）：`IslandModel.screenAway` 與 `animating`（`animationsEnabled && islandVisible && !screenAway && !hiddenByFullScreen`）。`IslandController.observeScreenAway()` 監聽 `screensDidSleep/Wake`、`sessionDidResignActive/BecomeActive`、distributed `com.apple.screenIsLocked/Unlocked`，原因存成 set，全部解除才恢復。`IslandView` 用 `model.animating` 驅動背景，並以 `\.islandAnimating` environment 傳給 `AgentSprite`（三處用法都在動態島視窗內）；清單卡片改用 `model.animating`。`IslandBackground.calm`（`!expanded && urgency == nil`）時海浪 `minimumInterval` 0.5。全套 468 個測試通過（皆為 AtollCore，這次沒有新增測試：改動都在 App 層的 view／通知接線）。
- 2026-11-13（agent）：實測（同一台機器、同樣的 agent，各自剛啟動 15 秒後每 3 秒取樣 6 次，收合）：修改前 4.8–5.8%（平均約 5.3%），修改後 0.4–1.5%（平均約 0.8%）。螢幕睡眠／鎖定的暫停沒有實測（無法在 session 內觸發），展開時 5 fps 與海浪 2 fps 的觀感需要目視確認。
