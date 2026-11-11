# 17: pixelfx 特效層

**What to build:** 用 pixelfx（MIT）離線產生特效，以同一資源格式疊加在角色上：blocked 三種 kind 的圖示氣泡（Question、Permission、Sign-in required）、送出訊息時的飛出效果、Done 時的小慶祝。送出飛出效果接上 10 的送出狀態（Delivered 時播放）。

**Blocked by:** 06, 10, 15

**Status:** resolved

- [x] 三種 blocked 圖示一眼可區分，且使用 15 的色盤
- [x] 送出飛出只在 Delivered 時播放，失敗時不播
- [x] Done 慶祝短促，結束後回到安靜待機
- [x] 特效遵守動畫開關與減少動態效果設定
- [x] pixelfx 產生腳本或參數保存在 art 目錄以便重現；不使用 NOTICE.md 排除的 Patch Pixel 字型

## Comments

- 2026-11-10（agent）：三種 blocked 氣泡（8×8，左上疊加）、`send` 飛出（只在送出成功時播放）、`celebrate`（Done 時播放），都遵守動畫開關與減少動態效果；已用 app 連拍驗證。**未完成**：特效是手繪，沒有用 pixelfx 產生。使用 pixelfx 需要抓取外部 repo 並可能安裝依賴，要先經使用者同意。資源格式已固定，改用 pixelfx 重產 `effects.png` 時 app 不需改動。
- 2026-11-11（agent）：經使用者同意改用 pixelfx 重產 `effects.png`。pixelfx 現成特效最小約 72px，縮到 16×16 會糊掉，所以照它的 make-your-own 流程，用 pixelfx core（`createFx`、Painter、`Rng`、`ease`、`composite`）寫兩個 16×16 的 Atoll 專用模組：`art/final/pixelfx/fx/send.js`（訊息卡從右手沿頭部右側飛出右上角，留 teal／梅紫尾跡）、`fx/celebrate.js`（頭頂上方一排爆一下，火花往兩側滑出、下垂、閃滅；左右鏡像）。`render.mjs` 依 12 fps 渲染，以 alpha 128 為門檻量化到色盤 `o`／`k`／`l`／`r`，輸出 `effects.frames.json`（commit 進 repo），`make_sprites.py` 改讀這份檔，仍是 app 資源唯一的寫入者，重產 sprite 不需要 Node。pixelfx 以 `fetch.sh` 抓固定 commit `044e12a` 到 gitignored 的 `vendor/`，只用 `src/core`，沒有 npm install，也不碰 `gallery/fonts` 的 Patch Pixel 字型。疊到三種頭型上檢查過：奶油色疊在奶油色頭上看不見，所以火花在頭部範圍內一律用 teal，飛出頭部後才轉白／奶油色。`send` 從 6 幀 0.5 秒改為 5 幀約 0.42 秒，`celebrate` 從 6 幀 0.6 秒改為 8 幀約 0.67 秒；資源格式不變，app 未改動。三種 blocked 圖示（`icons.png`，8×8 靜態）維持手繪：它們是圖示不是特效，pixelfx 不適用。
