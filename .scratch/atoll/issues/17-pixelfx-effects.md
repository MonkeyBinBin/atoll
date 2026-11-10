# 17: pixelfx 特效層

**What to build:** 用 pixelfx（MIT）離線產生特效，以同一資源格式疊加在角色上：blocked 三種 kind 的圖示氣泡（Question、Permission、Sign-in required）、送出訊息時的飛出效果、Done 時的小慶祝。送出飛出效果接上 10 的送出狀態（Delivered 時播放）。

**Blocked by:** 06, 10, 15

**Status:** ready-for-human

- [x] 三種 blocked 圖示一眼可區分，且使用 15 的色盤
- [x] 送出飛出只在 Delivered 時播放，失敗時不播
- [x] Done 慶祝短促，結束後回到安靜待機
- [x] 特效遵守動畫開關與減少動態效果設定
- [ ] pixelfx 產生腳本或參數保存在 art 目錄以便重現；不使用 NOTICE.md 排除的 Patch Pixel 字型

## Comments

- 2026-11-10（agent）：三種 blocked 氣泡（8×8，左上疊加）、`send` 飛出（只在送出成功時播放）、`celebrate`（Done 時播放），都遵守動畫開關與減少動態效果；已用 app 連拍驗證。**未完成**：特效是手繪，沒有用 pixelfx 產生。使用 pixelfx 需要抓取外部 repo 並可能安裝依賴，要先經使用者同意。資源格式已固定，改用 pixelfx 重產 `effects.png` 時 app 不需改動。
