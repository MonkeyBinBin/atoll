# 美術：風格探索 board（ticket 02）

總覽圖：`board/board.png`（3 方向 × 3 外觀，8× 預覽、色盤、動態島 1×／2× 預覽）。

## 共通規則

- 所有 sprite 都是手繪原生 16×16（`board/make_board.py` 內的像素字元圖），透明背景、對齊像素格、鎖定色盤；script 產圖時會檢查每個像素都在該方向色盤內。不是 AI 圖縮小。
- 三種外觀靠頭型剪影區分，三個方向共用同一套剪影語言：
  - **Claude Code**：寬圓頂頭（12px 寬）＋兩側耳栓，無天線。
  - **Codex**：平頂方盒頭＋全寬面罩，眼睛是兩條橫槓。
  - **通用**：小圓頭＋單根天線，天線頂端是個體色球。
- 個體色只上在配件區：圍巾（`S`/`s` 像素）與通用外觀的天線球。board 上三隻分別示範個體色 1／2／3。
- 個體色避開狀態色：個體色組只用藍、青、綠、紫、粉，不含紅、橙、黃；錯誤紅、等待黃、未知灰另列。
- 不含任何官方吉祥物或 logo 元素（無放射星形、無結形圖案）。
- 色盤：8 個角色色＋3 個狀態色＋3 組個體色（亮／暗）= 17 色。

## A / Neon Rim

冷色夜城招牌感。瘦長、有切角的機身，深色面罩配發光眼，左上緣青色亮邊；輪廓線是深靛色，在黑底上只當作內部分隔，外形靠亮邊與機身亮度撐出來。

| 角色 | Hex |
| --- | --- |
| outline（深靛） | `#2E3584` |
| body shadow / mid / light | `#4058B0` / `#6F90E8` / `#AFC8FF` |
| rim light（青） | `#8CF8FF` |
| visor | `#161B4A` |
| eye glow | `#ECFFFF` |
| joints / bolts | `#9AA6D6` |
| state：error / waiting / unknown | `#FF3B5C` / `#FFD23F` / `#7E849E` |
| individual 1（洋紅） | `#FF6AD5` / `#A3338C` |
| individual 2（綠） | `#7DFF8A` / `#2F9C4C` |
| individual 3（紫） | `#B98BFF` / `#5E40B5` |

## B / Toy Chunky

暖色軟膠玩具感。大頭短身、平塗兩階明暗、畫上去的深色眼睛；梅紫色輪廓在黑底上是柔和邊緣。三個方向中臉最有表情，1× 下也最容易認出是「角色」。

| 角色 | Hex |
| --- | --- |
| outline（梅紫） | `#7A3F6E` |
| body shadow / mid / light | `#E39A63` / `#FFE2B5` / `#FFF8EC` |
| visor / painted eye | `#4A2A58` / `#3A1F45` |
| joints / bolts（青綠） | `#7FD6C6` |
| specular dot | `#FFFFFF` |
| state：error / waiting / unknown | `#FF4A3D` / `#FFC93C` / `#9A8F8A` |
| individual 1（天藍） | `#5EC8FF` / `#2A6FB0` |
| individual 2（綠） | `#6EE07A` / `#2F8A4A` |
| individual 3（紫） | `#D78BFF` / `#7E43B0` |

## C / Pastel Soft

粉彩布偶感。圓潤團狀剪影、沒有線稿：邊緣是右下的抖色（dither）紫影加左上白色亮邊；柔和面罩配薄荷綠發光眼。

| 角色 | Hex |
| --- | --- |
| rim light | `#FFFFFF` |
| body light / mid / shadow | `#F1ECFF` / `#CFC4FF` / `#9483DA` |
| deep edge（局部） | `#6E5DB8` |
| visor | `#4A3E8E` |
| eye glow（薄荷） | `#7CFFD9` |
| bolts | `#B8F0FF` |
| state：error / waiting / unknown | `#FF5A6E` / `#FFE066` / `#A7A3B8` |
| individual 1（青） | `#6FE6FF` / `#2E8FB5` |
| individual 2（粉） | `#FF8FD8` / `#B04E93` |
| individual 3（綠） | `#A6F28C` / `#4E9B4E` |

注意：C 的 individual 2 粉色與 error 紅色相 hue 最近，若選 C 建議把它換成藍紫系。

## 檔案

```
art/
  imagegen-raw/          Codex imagegen 原始產出＋codex-log.txt
  board/
    make_board.py        sprite 像素圖與所有輸出的唯一來源
    board.png            總覽 board
    <direction>/
      {claude,codex,generic}-idle.png      原生 16×16，透明背景
      {claude,codex,generic}-idle@8x.png   8× nearest-neighbor，黑底
      palette.png / palette.txt            色票圖與 hex＋角色清單
      island@1x.png / island@2x.png        黑色膠囊條上的動態島尺寸預覽（1px = 1pt）
```

`<direction>`：`a-neon-rim`、`b-toy-chunky`、`c-pastel-soft`。

## 重新產生

```sh
python3 .scratch/atoll/art/board/make_board.py
```

只需 Pillow（已在 Pillow 12 驗證）。改 sprite 就改 script 內的 16 行字元圖，圖例寫在 script 開頭。

## Imagegen 探索

`codex exec`（built-in ImageGen）以 neon rim、chunky vinyl-toy、pastel plush 三組 prompt 各產出一張概念圖。Codex 在 art 目錄內沒有寫入權限（`Operation not permitted`），圖片落在 `~/.codex/generated_images/`，事後複製為 `imagegen-raw/concept-{a-neon-rim,b-toy-chunky,c-pastel-soft}.png`；完整過程見 `imagegen-raw/codex-log.txt`。概念圖只作風格參考，16×16 sprite 全部手繪。

## Decision

**B / Toy Chunky**，使用者於 2026-11-10 選定。

板上已知的代價（奶油色機身最接近等待黃）以兩點處理：等待狀態一律搭配 8×8 黃色圖示氣泡與舉手動作，不靠變色；個體色只出現在圍巾與天線球。

## 定稿（tickets 15–17）

唯一來源：`final/make_sprites.py`（Pillow），直接寫入 app 資源 `Sources/Atoll/Resources/Sprites/`，並在 `final/` 產出 QA 圖。

```sh
python3 .scratch/atoll/art/final/make_sprites.py
```

### 色盤（`final/palette.json`）

| 用途 | Hex |
| --- | --- |
| outline / body shadow / mid / light | `#7A3F6E` / `#E39A63` / `#FFE2B5` / `#FFF8EC` |
| visor / painted eye / joints（teal）/ specular | `#4A2A58` / `#3A1F45` / `#7FD6C6` / `#FFFFFF` |
| state：error / waiting / unknown（亮／暗） | `#FF4A3D` / `#FFC93C` / `#9A8F8A`、`#5E5652` |
| exited：dim body / dim outline / sleep z | `#6A4A62` / `#43283F` / `#A9B4FF` |

個體色 8 組（亮／暗），script 會檢查有彩度者與錯誤紅、等待黃的色相距離至少 40°：

`#5EC8FF/#2A6FB0`（sky）、`#6EE07A/#2F8A4A`（green）、`#D78BFF/#7E43B0`（violet）、`#7A8CFF/#3A47B0`（indigo）、`#F06BE6/#9A2E92`（magenta）、`#5EF0E8/#1F8F8A`（cyan）、`#F4F4FF/#9A9AB8`（silver）、`#A8F060/#5A9A2A`（lime）。

配件區（圍巾、generic 天線球）在 sprite sheet 中以 key color `#FF00FF`（亮）／`#B000B0`（暗）繪製，app 載入時換成該 agent 的個體色組（JSON `meta.accessoryKey` / `accessoryKeyDark`）。

### 動畫（每種外觀 33 幀）

| tag | 幀 | 播放 | 內容 |
| --- | --- | --- | --- |
| starting | 4 | 一次 → working | 抖散顯形＋火花；第 0 幀已可見剪影 |
| working | 6 | 循環 | 0/1 為輕微上下（呼吸對），2–5 雙手打字 |
| needs_you | 4 | 循環 | 右手舉過頭頂揮動；kind 氣泡由 app 疊加（`icons.png`） |
| done | 6 | 一次 → idle | 雙手歡呼、跳兩格、火花 |
| idle | 4 | 循環 | 0/1 輕微上下，第 3 幀半眨眼 |
| error | 4 | 一次，停最後一幀 | 紅眼＋「!」、左右抖、垮下 |
| interrupted | 3 | 一次 | 雙手張開「停」 |
| exited | 1 | 靜止 | 變暗、閉眼、z |
| unknown | 1 | 靜止 | 灰階＋「?」 |

每個 tag 的第 0 幀單獨看都能辨識狀態（減少動態效果時只顯示第 0 幀）。app 收合態播放 4 秒後改為第 0／1 幀 1Hz 交替，所以循環動畫的 0／1 幀設計成細微的呼吸對。

### 圖示與特效

- `icons.png`（8×8）：`question`（對話框＋?）、`permission`（對話框＋勾選框）、`auth`（鎖頭），黃底梅紫線，疊在角色左上。
- `ui.png`（12×12 UI 圖示）：`list`（清單板：奶油紙、teal 圓點、深色線條）與 `list_open`（往上抬 1px、圓點轉等待黃），用於動態島右端的清單按鈕，不使用系統圖示。
- `deco.png`（5×5）：`twinkle`（奶油色）與 `twinkle_teal` 閃爍星星（點 → 十字 → 大十字 → 十字），只出現在展開時頂列左右兩端的空白處。動態島其餘裝飾（頂部純黑 → 底部深梅紫 `#1C0E1E` 的漸層、角色腳下的梅紫舞台點線、依最急狀態著色的 1px 底緣）由 app 以同一色盤繪製；設定的 Decorations 可關閉，回到純黑。
- `effects.png`（16×16 疊加層）：`send`（訊息卡從右手飛出，送出成功時播放，失敗不播）、`celebrate`（頭頂火花擴散，Done 時播放）。兩者都遵守動畫開關與減少動態效果。
- **與 ticket 17 的偏差**：特效是在 `make_sprites.py` 中手繪，沒有使用 pixelfx。原因是使用 pixelfx 需要抓取外部 repo 並可能安裝依賴，這一步要先經使用者同意；目前的資源格式不變，之後改用 pixelfx 產生 `effects.png` 時 app 不需改動。

### QA 檔

`final/qa-all-tags@8x.png`（三種外觀 × 全部幀，套個體色）、`final/qa-effects@8x.png`、`final/island@1x.png` / `island@2x.png`（動態島尺寸）。

## App 圖示

`codex exec`（built-in ImageGen，`--sandbox workspace-write`，附 `b-toy-chunky/claude-idle@8x.png` 與動態島截圖當參考）產出三個候選：`app-icon/icon-a.png`（膠囊島＋探頭機器人）、`icon-b.png`（俯視環礁＋機器人）、`icon-c.png`（大頭特寫）。prompt 與過程見 `app-icon/prompt.txt`、`app-icon/codex-log.txt`，對照圖（含 64／32／16px）為 `app-icon/compare.png`。

採用 **B / 環礁**：直接對應 Atoll 名稱，16px 下仍能辨識環形與青色潟湖。

- 原始檔：`assets/AppIcon.icon`（Icon Composer 格式）。圖層 `Assets/atoll.png` 是從 `icon-b.png` 裁出 tile、以背景色 `#230822` 鋪滿的 1024² 無遮罩圖，圓角與陰影交給系統。
- `scripts/build-app.sh` 以 `actool` 編譯成 `Assets.car`＋`AppIcon.icns`（`CFBundleIconName` / `CFBundleIconFile`）；沒有 Xcode 時改複製預先編好的 `assets/AppIcon.icns`。
- 直接放 legacy `.icns`（自帶 squircle）會被 macOS 26 包進灰色外框，所以改走 `.icon`。
