# 🌿 PlantVoiceApp (生態樣區語音辨識系統)

A smart, AI-powered field data collection tool designed to streamline ecological surveys and plant biology research. 

透過語音辨識與 AI 結構化萃取技術，調查員在野外只需自然口述，系統即可自動將錄音轉換為精準的生態樣區數據表，大幅降低手寫紀錄的負擔與後續登打時間。

## ✨ 核心功能 (Key Features)

*   🎙️ **語音輸入與轉譯 (Speech-to-Text):** 支援現場錄音或上傳音檔 (MP3/WAV)，一鍵轉換為逐字稿，並提供即時校閱與手動修改。
*   🧠 **AI 智慧萃取 (AI Data Extraction):** 自動將口述內容萃取出「樣區編號」、「植物物候」、「伴生植物」、「土壤數值」等結構化生態欄位。
*   📍 **現場環境紀錄 (Environmental Context):** 支援拍攝現場照片與一鍵獲取高精度 GPS 座標。
*   🔐 **本地隱私安全 (Local Privacy):** API 金鑰僅儲存於設備本機 (SharedPreferences)，並提供「一鍵徹底銷毀」功能，絕不上傳雲端。
*   📊 **無縫資料匯出 (Seamless Export):** 支援將調查清單匯出為 CSV 與 TSV 格式，方便後續直接貼入 Notion 資料庫或 Excel 進行分析。

## 🤖 支援的 AI 引擎

本系統支援彈性切換主流 AI 服務進行資料萃取：
*   **Google Gemini** (支援直接音檔辨識與文字萃取)
*   **OpenAI** (Whisper-1 語音辨識 + GPT-4o 系列萃取)
*   **Anthropic Claude** (Claude 3 系列文字萃取)

## 📖 實際使用情境 (Use Case)

非常適合用於需要記錄多維度數據的田野調查。
例如，在進行 *Brassica rapa* 或 *Brassica oleracea* 等特定植物的野外棲地調查時，調查員只需口述：
> 「植物編號 BR-01 是 *Brassica rapa*，葉高 35 公分，目前的物候狀態是展葉和花苞，旁邊主要的伴生植物是大花咸豐草，屬於草本層 H...」

系統即可自動將龐雜的特徵分門別類填入對應的資料欄位中。

## 🚀 如何開始 (Getting Started)

1. Clone 本專案至本機：
   ```bash
   git clone [https://github.com/weimochi/PlantVoiceApp.git](https://github.com/weimochi/PlantVoiceApp.git)
