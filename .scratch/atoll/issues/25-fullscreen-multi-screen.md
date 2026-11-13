# 25: 全螢幕與多螢幕

**What to build:** 兩件事。第一，動態島所在螢幕的前景 app 進入全螢幕時，依設定「In full screen」調整動態島：Show all（維持現狀）／Attention only（收合態只顯示 Needs you 與 Error 的角色，沒有的話整個隱藏）／Hide（整個隱藏），預設 Attention only。第二，設定的「Screen」新增「Follow mouse」選項：動態島跟著游標所在的螢幕移動。

**Blocked by:** —

**Status:** resolved

- [ ] 事前驗證：找出不需要 Screen Recording／Accessibility 權限、也能可靠判斷「某個螢幕的前景 app 是否全螢幕」的方法（候選：`CGWindowListCopyWindowInfo` 找前景 app 中 layer 0、bounds 等於螢幕 frame 的視窗；只讀 bounds 與 owner，不讀視窗標題），並在 Comments 記下結論。另外確認以下情況不會誤判：開啟「自動隱藏選單列」、無邊框但沒有全螢幕的視窗、影片在瀏覽器內全螢幕
- [x] 進出全螢幕時（`activeSpaceDidChange`、前景 app 改變）重新判斷，不用高頻輪詢
- [x] Attention only：收合態只排入需要注意的角色，泡泡只出現在顯示中的角色上；全部恢復正常狀態時隱藏動態島，又有 agent 需要注意時再出現
- [x] Hide：收合態與泡泡都隱藏
- [x] 不論哪一種模式，全域快捷鍵（`⌥⌘A`、`⌃⌥⌘A`）照常展開清單或面板；通知不受影響
- [x] Follow mouse：以低頻率（約 1 秒）檢查游標所在螢幕，換螢幕時移過去；展開狀態（清單、面板、啟動表單）下不移動，收合後才跟過去；螢幕拔除時退回內建螢幕
- [x] 「Screen」原本的選項（Automatic／指定螢幕）行為不變
- [x] 「全螢幕時要顯示哪些角色」的篩選規則放在 AtollCore，並有測試（三種模式 × 有無需要注意的 agent）；視窗定位、全螢幕偵測不做自動化測試，用 debug hook 截圖驗證

**Out of scope:** 每個螢幕各放一個動態島、依 app 個別設定、Stage Manager 的特殊處理。

## Comments

- 2026-11-11（agent）：**事前驗證結論**：全螢幕的 space 裡，會有一個 layer 0 的視窗 bounds 正好等於螢幕 frame（CG 座標，原點在主螢幕左上），上方另有一條 32～44pt 的標題列 strip；一般、最大化、平鋪的視窗都停在選單列、Dock 或間隙，不會等於 frame。這個判斷要逐個螢幕做：實測時 Herdr 在上方螢幕全螢幕，而前景 app 在另一個螢幕。只讀 bounds、layer、pid，在沒有 Screen Recording 權限的 Atoll 裡實測可用（`kCGWindowName` 才需要權限，不讀）。**未實測的情況**：開啟「自動隱藏選單列」時最大化的視窗（理論上若 Dock 也隱藏，bounds 可能剛好等於 frame 而誤判）、瀏覽器內的 HTML5 影片全螢幕、無邊框且剛好蓋滿螢幕的視窗（會被當成全螢幕，視覺上也確實是）。
- 2026-11-11（agent）：實作：`FullScreenPresence.collapsedAgents`（AtollCore）決定收合態要排入哪些角色，nil 代表隱藏；`FullScreenDetector` 在 `activeSpaceDidChange`、`didActivateApplication`、換螢幕時於 0／0.7／1.6 秒各檢查一次（等全螢幕動畫結束）。`IslandModel.hiddenByFullScreen` 只在收合態成立，所以快捷鍵展開照常出現，收合後再隱藏；泡泡在隱藏時不出現，Attention only 時只給顯示中的角色。Follow mouse 以 `displayID = UInt32.max` 表示，每秒檢查游標所在螢幕，展開時不移動。順手修掉一個既有的耦合：`AppDelegate.applySettings` 在追蹤範圍內同步呼叫 `refreshScreen()`，連帶追蹤了 `mode` 與 `agents`，導致展開時重新選螢幕，且每次 agent 狀態變化都重新定位；改成延到追蹤範圍外執行。另外，來源離線時 agent 為 Unknown，不算需要注意，所以 Attention only 下動態島會隱藏。
- 2026-11-11（agent）：dev-run 實測（以探測程式在主螢幕開原生全螢幕視窗，OSC 7501 做假狀態）：全螢幕＋只有 Working → 隱藏；測試 agent 轉 Needs you → 出現且只排入它、泡泡在它上方；離開全螢幕 → 恢復全部；隱藏時展開清單 → 出現，收合 → 再隱藏；Follow mouse 游標移到上方螢幕 → 跟過去（該螢幕因 Herdr 全螢幕而隱藏），展開時移回下方 → 不動，收合後 1.2 秒內跟過去。Hide 模式只有單元測試，未實測；螢幕拔除時退回的行為也未實測。第一條的偵測方法已確認，但列出的三種誤判情況都還沒驗證，所以維持未勾選。`FullScreenPresenceTests` 5 個測試，全套 157 個通過。

- 2026-11-13（agent）：未驗證的誤判情境、Hide 模式與螢幕拔除拆到 53。
