import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart' show placemarkFromCoordinates;
import 'package:google_generative_ai/google_generative_ai.dart';

// 請務必確認 API Key 有效
const String kGeminiApiKey = 'YOUR_GEMINI_API_KEY_HERE'; // 替換為你的 Gemini API Key
// 使用 Flash 模型速度較快且便宜
const String kGeminiModel = 'gemini-2.5-flash';

void main() {
  runApp(const PlantVoiceApp());
}

class PlantVoiceApp extends StatelessWidget {
  const PlantVoiceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Plant-related speech-to-text classification (Gemini AI)',
      theme: ThemeData(colorSchemeSeed: Colors.green, useMaterial3: true),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _recorder = AudioRecorder();
  bool _isRecording = false;
  bool _isAnalyzing = false; // 新增：API 請求中的狀態
  String? _lastFilePath;

  // 口述文字
  final _inputController = TextEditingController(
      text:
          "This species is a perennial herb with an erect stem reaching 40–75 cm in height. Leaves are arranged alternately; blades are narrowly lanceolate to elliptic, measuring 5–11 cm in length and 1–2.5 cm in width, with finely serrate margins. The adaxial surface is glabrous and dark green, while the abaxial surface shows faint, reticulate venation. Inflorescences are terminal racemes; flowers with a 5-lobed calyx and pale yellow corolla. Stamens number 8 to 10, filaments slender. The ovary is superior, maturing into a dry, dehiscent capsule with numerous minute seeds. The species typically inhabits montane forests at elevations of 900–1600 m, preferring well-drained, slightly acidic soils");
  Map<String, dynamic>? _parsed;
  File? _imageFile;
  Position? _position;
  String? _address;

  final List<Map<String, dynamic>> _records = [];

  // 初始化 Gemini Model
  late final GenerativeModel _model;

  @override
  void initState() {
    super.initState();
    // 初始化模型，設定回傳格式為 JSON
    _model = GenerativeModel(
      model: kGeminiModel,
      apiKey: kGeminiApiKey,
      generationConfig: GenerationConfig(responseMimeType: 'application/json'),
    );
  }

  // ====== 錄音 ======
  Future<void> _toggleRecord() async {
    if (_isRecording) {
      final path = await _recorder.stop();
      setState(() {
        _isRecording = false;
        _lastFilePath = path;
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Recording saved：${_lastFilePath ?? ""}')),
        );
      }
      return;
    }

    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('Microphone permission is required to record audio')),
        );
      }
      return;
    }

    final dir = Directory.systemTemp.path;
    final filePath =
        '$dir/plant_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
      const RecordConfig(
          encoder: AudioEncoder.aacLc, bitRate: 128000, sampleRate: 44100),
      path: filePath,
    );
    setState(() => _isRecording = true);
  }

  // ====== 改用 Gemini 解析文字 ======
  Future<void> _parseTextWithGemini() async {
    final text = _inputController.text;
    if (text.trim().isEmpty) return;

    if (kGeminiApiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please set GEMINI_API_KEY')));
      return;
    }

    setState(() {
      _isAnalyzing = true;
      _parsed = null;
    });

    try {
      // 定義 Prompt：告訴 AI 你的數據結構 schema
      final prompt = '''
       

      使用者描述：
      "$text"

      【嚴格指令】：
      1. **輸出格式**：所有分類特徵必須是 **"中文 (Botanical English Term)"**。
      2. **變異處理**：
         - 若顏色或形狀有多種（例：白色或淡黃），請完整保留（例："白色或淡黃 (White or Pale Yellow)"）。
         - 若為範圍數值（例：雄蕊 10-12 枚），請保留範圍（例："10-12枚 (10-12)"）。
      3. **數值與單位換算 (重要)**：
         - 所有長度數值欄位 (Key 結尾為 _cm)，**必須自動換算為「公分 (cm)」**。
         - 例如：描述 "高 1.5 公尺" -> 輸出 150 (不是 1.5)。
         - 若為區間 (如 1.5-2.3 公尺)，請先換算再取**平均值** (例: (150+230)/2 = 190)。
      4. **格式**：請將輸出格式「攤平 (Flatten)」為單層 JSON 物件。

      請依照以下欄位結構填寫 (Key 格式: 類別 特徵 (中文))：
      {
        // --- 一般資訊 ---
        "General Life Span (壽命)": String (例: "多年生 (Perennial)"),
        "General Habitat 棲地": String,
        "General GrowthForm (習性)": String (例: "草本 (Herb)"),
        "General PlantHeight (株高 /cm)": Number (取平均值),

        // --- 根與莖 ---
        "Root Type (根類型)": String (例: "根狀莖 (Rhizome)"),
        "Stem Texture (莖質地)": String,
        "Stem Shape (莖形狀)": String,
        "Stem Surface (莖表面)": String,

        // --- 葉 (Leaf) ---
        "Leaf Arrangement (葉序)": String (例: "互生 (Alternate)"),
        "Leaf Type (複葉類型)": String (例: "單葉 (Simple)", "三出複葉 (Ternate)"), // ★ 補回來了
        "Leaf Shape (葉形)": String (例: "披針形至橢圓形 (Lanceolate to Elliptic)"), 
        "Leaf Margin (葉緣)": String (例: "細鋸齒 (Serrulate)"),
        "Leaf Apex (葉尖)": String,
        "Leaf Base (葉基)": String,
        "Leaf Venation (葉脈)": String (例: "羽狀脈 (Pinnate)"),
        "Leaf Stipule (托葉)": String,
        "Leaf Petiole (葉柄)": String,
        "Leaf Length (長 /cm)": Number (取平均值),
        "Leaf Width (寬 /cm)": Number (取平均值),

        // --- 花 (Flower) ---
        "Flower Inflorescence (花序)": String (例: "總狀 (Raceme)"),
        "Flower Bracts (苞片)": String, // 
        "Flower Color (花色)": String (例: "白色或淡黃 (White or Pale Yellow)"), 
        "Flower Petals (花瓣)": String (例: "5枚 (5)"),
        "Flower Stamens (雄蕊)": String (例: "10-12枚 (10-12)", "多數 (Numerous)"),
        "Flower Calyx (花萼)": String (例: "5裂 (5-lobed)"), 
        "Flower Ovary (子房位置)": String (例: "子房上位 (Superior)"),
        "Flower Sexuality (性別)": String (例: "兩性花 (Bisexual)"), // ★ 補回來了
        "Flower Symmetry (對稱性)": String,
        "Flower Diameter (花徑 /cm)": Number,

        // --- 果實 (Fruit) ---
        "Fruit Type (果實類型)": String (例: "小堅果 (Nutlet)"),
        "Fruit Description (果實描述)": String (例: "褐色具縱紋 (Brown, striate)"),
        
        // --- 其他 ---
        "Other Smell (氣味)": String, 
        "Other Sap (乳汁)": String, 
        "Other Note (備註)": String (例: "偏好微酸性壤土")
      }
      
      只回傳 JSON 物件。
      ''';

      final content = [Content.text(prompt)];
      final response = await _model.generateContent(content);

      if (response.text != null) {
        // 解析 JSON
        final Map<String, dynamic> jsonResult = jsonDecode(response.text!);

        // 加上原文欄位
        jsonResult['原文'] = text;

        setState(() {
          _parsed = jsonResult;
        });
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('解析失敗: $e')));
      }
    } finally {
      setState(() {
        _isAnalyzing = false;
      });
    }
  }

  // ====== 拍照 / 選圖 ======
  Future<void> _takePhoto() async {
    final picker = ImagePicker();
    final x =
        await picker.pickImage(source: ImageSource.camera, imageQuality: 85);
    if (x != null) setState(() => _imageFile = File(x.path));
  }

  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    final x =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (x != null) setState(() => _imageFile = File(x.path));
  }

  // ====== 取得定位 ======
  Future<void> _getLocation() async {
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('未取得定位權限')));
      }
      return;
    }
    final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best);
    setState(() => _position = pos);

    try {
      final placemarks =
          await placemarkFromCoordinates(pos.latitude, pos.longitude);
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        setState(() => _address =
            '${p.administrativeArea ?? ''}${p.locality ?? ''}${p.street ?? ''}');
      }
    } catch (_) {}
  }

  // ====== 加入清單 ======
  void _addCurrentRecord() {
    if (_parsed == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please parse one record first')));
      return;
    }
    final withMeta = {
      'timestamp': DateTime.now().toIso8601String(),
      ..._parsed!,
      'Image path': _imageFile?.path ?? '',
      'Latitude': _position?.latitude,
      'Longitude': _position?.longitude,
      'Horizontal accuracy (m)': _position?.accuracy,
      'Address': _address ?? '',
      'Audio file path': _lastFilePath ?? '',
    };
    _records.add(withMeta);
    setState(() {});
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已加入清單')));
  }

  // ====== 匯出 CSV ======
  Future<void> _exportCsv() async {
    if (_records.isEmpty && _parsed == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('尚無資料可匯出')));
      return;
    }

    final list = _records.isNotEmpty
        ? _records
        : [
            {
              'timestamp': DateTime.now().toIso8601String(),
              ...?_parsed,
              'Image path': _imageFile?.path ?? '',
              'Latitude': _position?.latitude,
              'Longitude': _position?.longitude,
              'Horizontal accuracy (m)': _position?.accuracy,
              'Address': _address ?? '',
              'Audio file path': _lastFilePath ?? '',
            }
          ];

    final headers = <String>{
      // 1. 系統資訊
      'timestamp',

      // 2. 一般資訊
      'General LifeSpan (壽命)',
      'General Habitat (棲地)',
      'General GrowthForm (習性)',

      // 3. 根與莖
      'Root Type (根類型)',
      'Stem Texture (莖質地)',
      'Stem Shape (莖形狀)',
      'Stem Surface (莖表面)',
      'General PlantHeight (株高 /cm)',

      // 4. 葉部特徵 (最重要，放前面)
      'Leaf Arrangement (葉序)',
      'Leaf Type (複葉類型)',
      'Leaf Shape (葉形)',
      'Leaf Margin (葉緣)',
      'Leaf Apex (葉尖)',
      'Leaf Base (葉基)',
      'Leaf Venation (葉脈)',
      'Leaf Stipule (托葉)',
      'Leaf Petiole (葉柄)',
      'Leaf Length (長 /cm)',
      'Leaf Width (寬 /cm)',

      // 5. 花部特徵
      'Flower Inflorescence (花序)',
      'Flower Color (花色)',
      'Flower Shape (花形)',
      'Flower Symmetry (對稱性)',
      'Flower Sexuality (性別)',
      'Flower Ovary (子房位置)',
      'Flower Petals (花瓣)',
      'Flower Stamens (雄蕊)',
      'Flower Calyx (花萼)',
      'Flower Bracts (苞片)',
      'Flower Diameter (花徑 /cm)',

      // 6. 果實與其他
      'Fruit Type (果實類型)',
      'Other Smell (氣味)',
      'Fruit Description (果實描述)',
      'Other Sap (乳汁)',

      // 7. 其他與備註
      'Other Note (備註)',

      // 8. 原始資料與多媒體
      'Original text',
      'Image path',
      'Latitude',
      'Longitude',
      'Horizontal accuracy (m)',
      'Address',
      'Audio file path'
    }.toList();

    final buffer = StringBuffer();
    buffer.writeln(headers.join(','));
    for (final row in list) {
      final line = headers.map((h) {
        final v = row[h];
        final s = (v == null) ? '' : v.toString().replaceAll('"', '""');
        return '"$s"';
      }).join(',');
      buffer.writeln(line);
    }

    final dir = await getApplicationDocumentsDirectory();
    final file = File(
        '${dir.path}/plant_voice_${DateTime.now().millisecondsSinceEpoch}.csv');
    await file.writeAsString(buffer.toString());
    await Share.shareXFiles([XFile(file.path)], text: 'Export CSV');
  }

  // ====== 匯出 JSONL ======
  Future<void> _exportJsonl() async {
    if (_records.isEmpty && _parsed == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No data available for export')));
      return;
    }
    final list = _records.isNotEmpty
        ? _records
        : [
            {
              'timestamp': DateTime.now().toIso8601String(),
              ...?_parsed,
              'Image path': _imageFile?.path ?? '',
              'Latitude': _position?.latitude,
              'Longitude': _position?.longitude,
              'Horizontal accuracy (m)': _position?.accuracy,
              'Address': _address ?? '',
              'Audio file path': _lastFilePath ?? '',
            }
          ];

    final sb = StringBuffer();
    for (final r in list) {
      sb.writeln(jsonEncode(r));
    }

    final dir = await getApplicationDocumentsDirectory();
    final file = File(
        '${dir.path}/plant_voice_${DateTime.now().millisecondsSinceEpoch}.jsonl');
    await file.writeAsString(sb.toString(), flush: true);
    await Share.shareXFiles([XFile(file.path)], text: 'Export JSONL');
  }

  @override
  void dispose() {
    _inputController.dispose();
    _recorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 渲染表格資料
    final parsedRows = _parsed?.entries
            .map((e) => DataRow(cells: [
                  DataCell(Text(e.key)),
                  DataCell(Text('${e.value ?? ''}'))
                ]))
            .toList() ??
        [];

    final List<DataRow> tableRows = [
      DataRow(cells: [
        const DataCell(Text('Plant')),
        DataCell(
          _imageFile != null
              ? Image.file(_imageFile!,
                  width: 80, height: 80, fit: BoxFit.cover)
              : const Text('（Unselected）'),
        ),
      ]),
      DataRow(cells: [
        const DataCell(Text('Coordinates')),
        DataCell(
          Text(
            _position != null
                ? '${_position!.latitude.toStringAsFixed(6)}, ${_position!.longitude.toStringAsFixed(6)}'
                    '${_position!.accuracy != null ? '（±${_position!.accuracy!.toStringAsFixed(1)}m）' : ''}'
                    '${_address != null && _address!.isNotEmpty ? '｜$_address' : ''}'
                : '（Unselected）',
          ),
        ),
      ]),
      ...parsedRows,
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text(
            'Plant-related speech-to-text classification (Gemini AI)'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ① 錄音 + 媒體/定位工具
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('① Recording / Image / Location',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: _toggleRecord,
                          icon: Icon(_isRecording ? Icons.stop : Icons.mic),
                          label: Text(_isRecording
                              ? 'Stop Recording'
                              : 'Start Recording'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isRecording ? Colors.red : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        if (_lastFilePath != null)
                          Expanded(
                              child: Text('Latest Recording：$_lastFilePath',
                                  overflow: TextOverflow.ellipsis)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _takePhoto,
                          icon: const Icon(Icons.photo_camera),
                          label: const Text('拍照'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _pickFromGallery,
                          icon: const Icon(Icons.photo_library),
                          label: const Text('選圖'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _getLocation,
                          icon: const Icon(Icons.my_location),
                          label: const Text('取得位置'),
                        ),
                      ],
                    ),
                    if (_imageFile != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(_imageFile!,
                              width: 120, height: 120, fit: BoxFit.cover),
                        ),
                      ),
                    if (_position != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '座標：${_position!.latitude.toStringAsFixed(6)}, ${_position!.longitude.toStringAsFixed(6)}'
                          '${_position!.accuracy != null ? '（±${_position!.accuracy!.toStringAsFixed(1)}m）' : ''}'
                          '${_address != null && _address!.isNotEmpty ? '｜$_address' : ''}',
                          style: const TextStyle(color: Colors.black54),
                        ),
                      ),
                  ]),
            ),
          ),

          // ② 文字輸入 + Gemini 解析
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('② 口述文字 (AI 分析)',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _inputController,
                      maxLines: 6,
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        hintText: '例：葉互生，披針形... (可直接用語音輸入)',
                        suffixIcon: IconButton(
                          onPressed: _inputController.clear,
                          icon: const Icon(Icons.clear),
                          tooltip: '清空',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                        // 如果正在分析，按鈕失效或顯示轉圈
                        onPressed: _isAnalyzing ? null : _parseTextWithGemini,
                        icon: _isAnalyzing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.auto_awesome),
                        label: Text(
                            _isAnalyzing ? 'Gemini 分析中...' : 'Gemini 解析 → 表格'),
                        style: FilledButton.styleFrom(
                          backgroundColor:
                              Colors.deepPurple, // 區隔原本的顏色，顯示這是 AI 功能
                        ),
                      ),
                    ),
                  ]),
            ),
          ),

          // ③ 解析結果
          if (_parsed != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('③ 解析結果',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('欄位')),
                            DataColumn(label: Text('值')),
                          ],
                          rows: tableRows,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: _addCurrentRecord,
                            icon: const Icon(Icons.add),
                            label: const Text('加入清單'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _exportCsv,
                            icon: const Icon(Icons.file_download),
                            label: Text('匯出 CSV（${_records.length} 筆）'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _exportJsonl,
                            icon: const Icon(Icons.data_object),
                            label: Text('匯出 JSONL（${_records.length} 筆）'),
                          ),
                        ],
                      ),
                    ]),
              ),
            ),

          // ④ 清單總覽
          if (_records.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('④ 已加入清單（共 ${_records.length} 筆）',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      ..._records.map((r) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                                '• ${r['timestamp']}｜${r['葉形'] ?? '-'}｜高${r['植株高_cm'] ?? '-'}cm'),
                          )),
                    ]),
              ),
            ),
        ],
      ),
    );
  }
}
