import 'dart:convert';
import 'dart:typed_data'; // 新增：處理 Bytes 位元資料，完美支援 Web
import 'package:google_generative_ai/google_generative_ai.dart';

class AiService {
  static Future<Map<String, dynamic>?> parseSurveyData({
    required String apiKey,
    required String promptText,
    Uint8List? audioBytes, // 更改：直接接收音訊的 Bytes，而不是路徑
  }) async {
    if (apiKey.isEmpty) return null;

    final model = GenerativeModel(
      model: 'gemini-2.5-flash',
      apiKey: apiKey,
      generationConfig: GenerationConfig(responseMimeType: 'application/json'),
    );

    // 建構 Prompt
    final systemPrompt = '''
      【嚴格指令】：
      1. 根據使用者的描述或錄音內容，將生態樣區調查資料萃取成 JSON 格式。
      2. 數值請僅保留數字，不需要附帶單位。
      3. 若未提及某個欄位，請填入 "" 或 null。
      4. 請將輸出格式攤平 (Flatten) 為單層 JSON 物件。

      請依照以下欄位結構填寫：
      {
        "樣區編號": String,
        "調查人員": String,
        "日期": String,
        "時間": String,
        "海拔高度 (m)": Number,
        "步道距離": String,
        "空氣溫度 (°C)": Number,
        "空氣相對溼度 (%)": Number,
        "岩石地比例 (%)": Number,
        "地表裸露度 (土的比例) (%)": Number,
        "凋落物覆蓋度 (無植被處) (%)": Number,
        "倒木覆蓋度 (%)": Number,
        "坡向": String,
        "坡度 (度)": Number,
        "土壤深度 (cm)": Number,
        "土壤含水量 (%)": Number,
        "土壤 pH": Number,
        "半球攝影": String,
        "備註": String,
        "樣區內_總株數": Number,
        "植物_編號": String,
        "植物_葉高 (cm)": Number,
        "植物_花高 (cm)": Number,
        "植物_物候": String,
        "伴生植物_物種": String,
        "伴生植物_階層": String,
        "伴生植物_高度 (m)": Number,
        "伴生植物_覆蓋度 (%)": Number
      }
      
      只回傳 JSON 物件。
    ''';

    List<Part> parts = [
      TextPart("使用者描述內容：\n$promptText\n\n$systemPrompt")
    ];

    // 如果有音訊位元資料，直接把資料丟給 Gemini 聽！
    // 這樣就不需要依賴 dart:io 的 File，Web 也能順暢執行。
    if (audioBytes != null) {
      parts.add(DataPart('audio/m4a', audioBytes));
    }

    final response = await model.generateContent([Content.multi(parts)]);

    if (response.text != null) {
      return Map<String, dynamic>.from(jsonDecode(response.text!));
    }
    return null;
  }
}