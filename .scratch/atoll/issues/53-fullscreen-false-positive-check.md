# 53: 驗證全螢幕偵測的誤判情境

**What to build:** 25 的全螢幕偵測（`FullScreenDetector.isFullScreen`）只看「該螢幕上有沒有 layer 0、非 Atoll 的視窗 bounds 正好等於螢幕 frame」，不看視窗是否真的進入原生全螢幕 space。25 列出的三種可能誤判、Hide 模式與螢幕拔除都還沒實測。逐一實測並在 Comments 記錄結果；確認會誤判且影響使用的，修正判斷（例如改成同時檢查 space 類型或標題列 strip），並補上對應驗證。

**Blocked by:** 25

**Status:** ready-for-human

- [ ] 開啟「自動隱藏選單列」且 Dock 也隱藏時，最大化（Option＋綠燈／雙擊標題列）的一般視窗不會被判成全螢幕
- [ ] 瀏覽器內 HTML5 影片全螢幕（例如 YouTube 按 `f`）：記錄是否判成全螢幕，以及這是否符合預期（視覺上它確實佔滿螢幕）
- [ ] 無邊框且剛好蓋滿螢幕、但不是原生全螢幕的視窗：記錄判斷結果，決定要不要視為全螢幕
- [ ] Hide 模式實測：全螢幕時收合態與泡泡都隱藏，快捷鍵仍能展開
- [ ] 螢幕拔除時退回內建螢幕（Follow mouse 與指定螢幕兩種設定）
- [ ] 若修改了判斷規則，原本已驗證的情境（原生全螢幕、多螢幕下只有其中一個螢幕全螢幕）不退化

**Out of scope:** Stage Manager、依 app 個別設定、每個螢幕各一個動態島。

## Comments

- 2026-11-13（agent）：從 25 拆出。需要改系統設定（自動隱藏選單列／Dock）、在瀏覽器操作影片全螢幕、實際拔螢幕，agent 無法代為操作（osascript 沒有 Accessibility 權限），所以標為 ready-for-human；結果可貼回這裡，再交給 agent 修正。
