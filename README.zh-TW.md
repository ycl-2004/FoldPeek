<p align="center">
  <img src="FoldPeekApp/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png" alt="FoldPeek 圖示" width="120" height="120">
</p>

<h1 align="center">FoldPeek</h1>

<p align="center">
  <strong>直接在 Finder 快速查看中，把資料夾瀏覽成唯讀的紙本索引。</strong>
</p>

<p align="center">
  <a href="https://github.com/ycl-2004/FoldPeek/releases/latest"><img src="https://img.shields.io/github/v/release/ycl-2004/FoldPeek?label=release&amp;color=111111" alt="最新版本"></a>
  <a href="https://github.com/ycl-2004/FoldPeek/releases"><img src="https://img.shields.io/github/downloads/ycl-2004/FoldPeek/total?label=downloads&amp;color=111111" alt="累計下載"></a>
  <img src="https://img.shields.io/badge/macOS-13.0%2B-111111?logo=apple&amp;logoColor=white" alt="macOS 13.0 或更高版本">
  <img src="https://img.shields.io/badge/Mac-Universal%202-111111?logo=apple&amp;logoColor=white" alt="支援 Apple Silicon 與 Intel 的通用 App">
  <img src="https://img.shields.io/badge/Swift-SwiftUI%20%C2%B7%20AppKit-F05138?logo=swift&amp;logoColor=white" alt="使用 SwiftUI 與 AppKit 建構">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-111111" alt="MIT 授權條款"></a>
</p>

<p align="center">
  <a href="https://github.com/ycl-2004/FoldPeek/releases/latest/download/FoldPeek.zip"><strong>⬇ 下載 macOS 版</strong></a>
  ·
  <a href="https://github.com/ycl-2004/FoldPeek/releases">版本發佈</a>
  ·
  <a href="#功能">功能</a>
  ·
  <a href="#隱私與安全性">隱私與安全性</a>
  ·
  <a href="#從原始碼建構">從原始碼建構</a>
  ·
  <a href="#授權">授權</a>
  ·
  <a href="README.md">English</a>
</p>

在 Finder 選擇資料夾並按下 **Space**。FoldPeek 會把普通的資料夾預覽替換成受限制、可展開的索引，以及可查看文字、程式碼、Markdown、PDF、Word 文件、圖片和檔案中繼資料的檢視器。它始終留在快速查看裡，不需要另外開啟檔案管理器視窗。

FoldPeek 的範圍刻意保持窄小。它以唯讀方式預覽資料夾，不發出網路請求、不啟動外部工具，也不儲存資料夾內容。宿主 App 的用途只有說明如何啟用快速查看擴充功能。

> **目前分發狀態：** 公開的 Universal 2 建構是 ad-hoc 簽名，尚未經 Apple 公證。因此 macOS 第一次啟動時需要明確信任。發佈版支援 Apple Silicon 與 Intel Mac；完整原始碼可供檢視與本機建構。

## 快速開始

1. **[下載 `FoldPeek.zip`](https://github.com/ycl-2004/FoldPeek/releases/latest/download/FoldPeek.zip)** 並解壓縮。
2. 將 `FoldPeek.app` 移到 `/Applications`。
3. 清除隔離標記——公開建構是 ad-hoc 簽名，尚未經公證：

   ```bash
   xattr -dr com.apple.quarantine /Applications/FoldPeek.app
   ```

4. 開啟**系統設定 → 一般 → 登入項目與擴充功能 → 快速查看**，啟用 **FoldPeek**。
5. 在 Finder 選擇資料夾並按下 **Space**。

### 系統需求

- macOS 13.0 或更高版本
- Apple Silicon（`arm64`）或 Intel（`x86_64`）Mac
- 執行時不需要帳號、套件相依性或網路連線

目前公開版本是 [`v1.0.0`](https://github.com/ycl-2004/FoldPeek/releases/tag/v1.0.0)，來自專案版本 `1.0 (build 1)`，並以 Xcode 26.6 完成驗證。

## 為什麼是 FoldPeek

- **留在 Finder 裡。** 不需開啟另一個視窗，也不會失去目前已選取的檔案，就能檢查資料夾內容。
- **從設計上保持唯讀。** 擴充功能只取得使用者選擇的唯讀檔案權限，不包含重新命名、刪除、移動、剪貼簿或啟動檔案的路徑。
- **只載入你要求的內容。** 第一層會立即顯示；子資料夾只有在展開後才讀取，搜尋也不會觸發目錄讀取。
- **原始碼就按原始碼處理。** 程式碼使用有上限的單次語法掃描器；Markdown 使用程序內的惰性渲染器，不依賴 HTML 或文件引擎。
- **不猜測文件讀取器。** Word、RTF 與 OpenDocument 檔案會明確指定要使用的 AppKit 讀取器，因此檔案無法自行進入 HTML 路徑。FoldPeek 無法讀取的格式會交給 Apple 自己的縮圖服務，在程序外繪製，而不是在這裡解析。
- **讓不可信輸入保持有界。** 目錄列舉、樹狀結構大小、預覽位元組數、圖片尺寸、語法上色與 Markdown 版面配置，都在程式碼中有硬性上限。

## 功能

**資料夾索引**

- 依類型分組資料夾自己的內容——資料夾、文件、試算表、投影片、圖片、影片、音訊、程式碼、文字、資料與封存檔；每組使用自己的標題線與色彩，名稱在組內自然排序。
- 顯示目前存在的所有群組圖例列；圖例同時是跳轉目標，不必捲動就能前往某一群組。
- 依類別替每一列的副檔名標籤上色，長清單可以先按類型掃描，不必逐一讀檔名。
- 從列上的任何位置展開或收合資料夾。
- 一次載入一層，所有面板共用項目預算與深度上限。
- 顯示符號連結項目，但不會刻意追蹤它們。
- 依名稱篩選已載入的節點，並顯示符合項目的路徑。

**檔案檢視器**

- 顯示類型、大小、修改日期、符號連結狀態與路徑；標題徽章使用項目類別色彩。
- 在不可編輯的 `NSTextView` 中預覽有上限的 UTF-8 文字。
- 為常見原始碼格式加入行號、縮排輔助線、語法色彩與括號深度色彩。
- 以安全的 Markdown 子集排版：標題、清單、表格、引文、強調、分隔線與圍欄程式碼。
- 透過 PDFKit 捲動多頁 PDF，停用連結註解，點擊不會開啟瀏覽器。
- 將 Word（`.doc`、`.docx`）、RTF 與 OpenDocument 文字重新排版到紙張介面，保留結構，但移除文件自己的字型與連結。
- 透過 ImageIO 解碼支援的圖片，產生最長邊不超過 2,048 px 的縮圖。
- 讀取 Pages、Keynote、Numbers 與部分 Office 檔案內已存在的首頁圖片；在程序內處理，不使用文件解析器。
- 將 Excel 活頁簿的工作表讀成有格線的表格，每張工作表各有一個分頁，可在頁面圖片與資料之間切換——二十張工作表比任何單張圖片多顯示十九張表。
- 其他格式回退到 Apple 的縮圖服務——包括 PowerPoint、舊版 Office，以及沒有內嵌圖片的 Keynote；這需要一個安全性說明中列出的命名 sandbox 例外。
- 對不支援或非一般檔案回退到中繼資料顯示。

**紙張介面**

- 固定的奶油色紙張、酒紅色識別色、牛仔藍結構、襯線正文與等寬技術細節。
- 快速查看面板內的索引窗格與內容窗格都可以調整大小。
- 刻意固定使用明亮色盤，不跟隨自動深色模式。

## 運作方式

```text
Finder 選取
      │
      ▼
快速查看擴充功能
      │
      ├── 有上限的單層目錄列舉
      ├── 延遲展開的索引 + 記憶體內篩選
      └── 有上限的文字、Markdown、PDF、文件或圖片預覽 + 中繼資料
```

擴充功能只註冊 `public.folder` 和 `public.directory`。由於檔案與子資料夾的讀取發生在初始預覽請求之後，它會在預覽面板存活期間保留 security-scoped 存取；面板消失後就釋放該存取權。

## 隱私與安全性

FoldPeek 沒有帳號、分析、廣告、遙測、更新服務或執行時網路存取，也不會保存資料夾清單或預覽過的檔案內容。

提交到儲存庫的 entitlements 刻意保持精簡：

| 目標 | Entitlements |
| --- | --- |
| 宿主 App | `com.apple.security.app-sandbox` |
| 快速查看擴充功能 | App Sandbox + `com.apple.security.files.user-selected.read-only` |

目前的上限由原始碼強制執行：

| 上限項目 | 限制 |
| --- | ---: |
| 每個目錄的項目數 | 2,000 |
| 每個預覽面板的總項目數 | 20,000 |
| 展開深度 | 8 層 |
| 每個檔案讀取的文字 | 256 KB |
| 接受的圖片檔案大小 | 64 MB |
| 解碼後圖片邊長 | 2,048 px |
| 接受的 PDF 檔案大小 | 512 MB |
| Word／RTF／OpenDocument 檔案大小 | 32 MB |
| 文件排版字元數 | 400,000 |
| 每張工作表的列數 | 400 |
| 每列的欄數 | 32 |
| 系統頁面渲染接受大小 | 512 MB |
| 系統頁面渲染逾時 | 8 秒 |
| 語法上色字元數 | 200,000 |
| Markdown 排版字元數 | 200,000 |

文字會保持惰性：停用富文字、圖形匯入、資料偵測器、可點擊連結與文字附件。圖片透過 ImageIO 在有上限的像素尺寸下解碼。PDF 頁面由 PDFKit 繪製，並關閉連結註解與資料偵測器。Word、RTF 與 OpenDocument 檔案由 AppKit 讀取，明確指定文件類型，不靠猜測，並在讀取後移除自己的連結。支援的 Office 容器只會被解析以取得有上限的內嵌預覽與活頁簿工作表；其他格式都交給 Apple 程序中的系統縮圖服務渲染，這裡不會解析。獨立封存檔瀏覽、HTML、SVG、子程序、外部 App 與背景輔助程式不在此版本範圍內。

信任邊界、可用能力、驗證清單與剩餘風險，請見 [`docs/SECURITY_AUDIT.md`](docs/SECURITY_AUDIT.md)。

## 目前版本

FoldPeek `v1.0.0` 是第一個公開 macOS 版本。App 是 Universal 2 建構，宿主 App 與快速查看擴充功能都包含原生 `arm64` 與 `x86_64` 可執行檔。

| 產物 | 用途 |
| --- | --- |
| `FoldPeek.zip` | 適用 macOS 13.0 或更高版本的 ad-hoc 簽名 Universal 2 App |
| `FoldPeek.zip.sha256` | 用於驗證下載內容的 SHA-256 校驗檔 |

請在同時包含兩個檔案的資料夾中驗證下載：

```bash
shasum -a 256 -c FoldPeek.zip.sha256
```

## 常見問題

<details>
<summary>為什麼搜尋會忽略尚未開啟的資料夾內檔案？</summary>

搜尋刻意只限於已載入的節點。按鍵不會遍歷目錄樹，因此篩選不會繞過深度與項目預算，也不會造成預期外的磁碟活動。

</details>

<details>
<summary>為什麼方向鍵會切換 Finder 選取項目，而不是在索引中移動？</summary>

快速查看面板開啟時，方向鍵由 Finder 管理。請在 FoldPeek 中使用滑鼠選取並展開列。

</details>

<details>
<summary>如何解除安裝 FoldPeek？</summary>

在**系統設定 → 一般 → 登入項目與擴充功能 → 快速查看**中關閉 **FoldPeek**，再把 `FoldPeek.app` 移到垃圾桶。FoldPeek 不會安裝輔助程式、LaunchAgent、登入項目或共用偏好設定儲存庫。

</details>

<details>
<summary>可以把建構好的版本傳給別人嗎？</summary>

請分享公開的 [`v1.0.0` 版本](https://github.com/ycl-2004/FoldPeek/releases/tag/v1.0.0) 與 [`INSTALL.md`](INSTALL.md)。此建構是 ad-hoc 簽名且未經公證，收件者必須明確信任它，並在開啟前清除 macOS 隔離標記。

</details>

## 從原始碼建構

<details>
<summary>需求、建構驗證與簽名說明</summary>

需求：

- macOS 13.0 或更高版本
- Xcode 15 或更高版本
- 不使用 Swift Package Manager 相依套件
- 共用專案未設定 Apple Developer Team

在 Xcode 開啟 `FoldPeek.xcodeproj`，選擇 `FoldPeek` scheme 和 **My Mac**，然後建構或執行。如果 Xcode 要求簽名設定，請選擇自己的 Team，或使用下方不簽名的驗證指令。

驗證不使用簽名身分的 Release 建構：

```bash
xcodebuild -project FoldPeek.xcodeproj \
  -scheme FoldPeek \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/FoldPeekDerivedData \
  SYMROOT=/tmp/FoldPeekBuild \
  OBJROOT=/tmp/FoldPeekIntermediates \
  CODE_SIGNING_ALLOWED=NO \
  build
```

儲存庫目前沒有自動化測試目標。Release 建構與 Xcode 靜態分析是目前可用的自動化驗證路徑。

手動封裝腳本會執行乾淨的 Universal 2 Release 建構，使用儲存庫 entitlements 重新簽名宿主 App 與擴充功能、驗證 bundle 簽名，並寫出 `dist/FoldPeek.zip` 與 `dist/FoldPeek.zip.sha256`。它不會安裝 App、修改 `/Applications`、註冊擴充功能、重啟 Finder 或下載工具。

</details>

## 專案結構

- `FoldPeekApp/` — SwiftUI 入門宿主 App、App entitlements 與視覺資源。
- `FoldPeekPreviewExtension/` — 快速查看控制器、索引 UI、原始碼／Markdown／活頁簿渲染與檢視器。
- `Shared/` — 檔案中繼資料、有界目錄載入、檔案預覽載入、ZIP／XML 輔助工具與活頁簿讀取。
- `FoldPeek.xcodeproj/` — 兩個目標的 Xcode 專案。
- `docs/DEVELOPMENT.md` — 架構、不變量、上限與驗證指引。
- `docs/SECURITY_AUDIT.md` — 目前的信任邊界、限制與剩餘風險。
- `scripts/package.sh` — 直接分享用的手動 ad-hoc 封裝腳本。
- `artwork/` — 用來產生提交版 App 圖示集的原始美術資源。

## 版本與發佈

`FoldPeek.xcodeproj/project.pbxproj` 中兩個目標的 `MARKETING_VERSION` 與 `CURRENT_PROJECT_VERSION` 是版本的唯一來源。目前原始碼版本是 `1.0 (build 1)`。

公開版本使用 `v<version>` 標籤，並附上固定命名的 `FoldPeek.zip` 與 `FoldPeek.zip.sha256`。未來版本應一起更新兩個目標，並明確寫出簽名與公證狀態。

## 已知限制

- ad-hoc 套件未經 Apple 公證，在其他 Mac 上需要手動信任。
- 搜尋只涵蓋目前預覽面板已載入的節點。
- 快速查看開啟時，方向鍵仍由 Finder 管理。
- 紙張色盤刻意保持明亮，不跟隨深色模式。
- 有內容預覽的格式包括有界文字、Markdown、PDF、文書處理文件、支援的點陣圖，以及支援的 XLSX／XLSM 活頁簿。
- 目錄、樹狀結構、文字、圖片、文件、PDF、活頁簿、上色與 Markdown 限制都是固定值。
- Xcode 專案目前沒有自動化測試目標或 CI 工作流程。

## 授權

FoldPeek 著作權所有 © 2026 YC，依 [MIT 授權條款](LICENSE)發佈。
