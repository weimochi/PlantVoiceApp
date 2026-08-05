# PlantVoiceApp (Ecological Survey Speech Recognition System)

A field data collection tool designed to streamline ecological surveys and plant biology research.

By combining speech recognition with AI-driven structured data extraction, field researchers can dictate observation notes naturally. The system automatically converts voice recordings into structured ecological survey tables, reducing manual paperwork and post-fieldwork data entry time.

## Key Features

* Speech-to-Text: Supports live field recording or audio file uploads (MP3/WAV), converting them into transcripts with real-time editing and manual review capabilities.
* AI Data Extraction: Automatically extracts and parses spoken content into structured fields, including plot ID, plant phenology, associated species, and soil metrics.
* Environmental Context Logging: Integrates photo capture and high-precision GPS coordinate retrieval.
* Local Privacy & Security: API keys are stored exclusively on the local device (SharedPreferences) with a one-click wipe feature, ensuring sensitive credentials are never uploaded to the cloud.
* Data Export: Enables exporting survey records to CSV and TSV formats for integration into Notion databases, Excel, or downstream analytical workflows.

## Supported AI Engines

The system supports configurable AI backends for speech recognition and data extraction:
* Google Gemini (Direct audio recognition and text extraction)
* OpenAI (Whisper-1 speech recognition + GPT-4o series text extraction)
* Anthropic Claude (Claude 3 series text extraction)

## Use Case Example

Designed for multi-parameter field surveys. For example, during an epiphytic plant survey, the investigator can dictate:

> 「這裡是樣區編號 PA-01，調查人員是威威。今天日期是2026年8月4日，時間早上10點。目前海拔高度大約 850 公尺，步道距離是 <5m。現場空氣溫度 26.5 度，空氣相對溼度高達 85%。環境部分，岩石地比例佔 10%，地表裸露度 5%，凋落物覆蓋度 60%，倒木覆蓋度 25%。坡向朝東北，坡度大約 15 度。地表土壤深度測量約 15 公分，土壤含水量 70%，土壤 pH 值 5.8。已經拍攝半球攝影。備註：植株附生於大葉楠主幹上，生長狀況良好。樣區內總株數有 3 株。現在紀錄的這株植物編號是 PA-01-A，目標是 Phalaenopsis amabilis var. formosana，葉高 18 公分，花高 25 公分，目前的物候狀態同時有展葉和花苞。旁邊主要的伴生植物是台灣山蘇花，屬於草本層 H，高度約 0.8 公尺，覆蓋度大概 30%。」

The system automatically parses and organizes these parameters into their respective database fields.

## Getting Started

1. Clone the repository:
   ```bash
   git clone [https://github.com/weimochi/PlantVoiceApp.git](https://github.com/weimochi/PlantVoiceApp.git)

## Acknowledgments

Special thanks to Prof. Shih-Hui Liu for inspiring the concept and workflow behind this field data collection tool.
