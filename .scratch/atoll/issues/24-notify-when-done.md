# 24: 從面板設定「這次跑完時通知我」

**What to build:** 互動面板標題列加一個鈴鐺按鈕。打開後，這個 agent 下一次跑完時發一則 macOS 通知，發完自動關閉（一次性）。目前依 agent／專案打開 Done 通知的設定（ticket 14）只在 Settings 視窗裡，而且是永久生效。跑長任務時常見的需求是「這一次跑完叫我」，所以把它放到面板上，做成一次性。

**Blocked by:** —

**Status:** resolved

- [x] 「跑完」的判斷：Working／Starting 之後轉為 Done、Exited，或沒有回報 Done 就轉為 Idle（跟泡泡的 Idle 規則相同）。其中任一個發生時通知並關閉鈴鐺
- [x] 轉為 Needs you 不算跑完，鈴鐺保持開啟（Needs you 原本就會通知）；轉為 Error 時關閉鈴鐺，不另外發通知（Error 原本就會通知）
- [x] 在 agent 已經是 Done／Idle 時打開鈴鐺，要等下一個回合跑完才通知，不會立刻發
- [x] 一次性狀態只存在記憶體，不寫入 `UserDefaults`；agent 被移除或 Atoll 重啟就消失
- [x] 跟 Settings 的永久設定並存：該 agent 或其專案已經在永久 Done 名單時，鈴鐺顯示為「永遠通知」（help 註明在 Settings 設定），不會重複通知同一次轉換
- [x] 清單列上對有開鈴鐺的 agent 顯示小鈴鐺圖示
- [x] 通知內容沿用隱私規則（「工具 · 專案名」＋狀態字），點擊打開該 agent 的面板；遵守通知總開關
- [x] 規則放在 AtollCore（擴充 `NotificationRules`／`NotificationSettings`，或由 `AgentStore` 管理一次性名單），並有測試：觸發後關閉、Needs you 保持開啟、Error 關閉但不另外通知、已 Done 時打開不立刻觸發、與永久名單不重複

**Out of scope:** 清理永久名單裡已不存在的 agent address、依專案的一次性通知。

## Comments

- 2026-11-11（agent）：一次性名單放在 `AgentStore.notifyWhenDone`（只存在記憶體，`rebuild()` 時清掉已移除的 agent），由 `toggleNotifyWhenDone` 切換。來源回報狀態轉換時，在 `onTransition` 之後判斷是否跑完：轉為 Done／Exited，或從 Working／Starting 轉為 Idle，就關閉並呼叫 `onNotifyWhenDone`；轉為 Error 只關閉；Needs you 保持開啟。因為一定要有轉換才會觸發，已是 Done 時打開會等到下一個回合。`NotificationRules.finished` 跟永久 Done 共用 `lastSent` 的 `done#turn` key，同一次轉換不會重複通知。通知總開關關閉時仍會關掉鈴鐺，只是不發通知。面板標題列有鈴鐺按鈕：`bell`／已開為 `bell.fill`／永久名單涵蓋時顯示 `bell.badge.fill` 並停用；清單列對已開鈴鐺的 agent 顯示小鈴鐺。`NotifyWhenDoneTests` 10 個測試，全套 152 個通過。尚未在實際 App 中試跑。

