import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart'; // 給 Uint8List 用的
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart' show placemarkFromCoordinates;
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart'; // ★ 新增：用來選取音檔

import 'settings_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _recorder = AudioRecorder();
  bool _isRecording = false;
  bool _isAnalyzing = false;
  bool _isTranscribing = false; // ★ 新增：控制轉文字的 Loading 狀態

  String? _lastFilePath;
  String? _audioFileName;
  Uint8List? _audioBytes; // ★ 新增：統一將音檔存成二進位資料（支援網頁版）

  // ★ 新增：第一區塊的逐字稿輸入框
  final _transcriptionController = TextEditingController();
  // 第二區塊的結構化文字輸入框
  final _inputController = TextEditingController();

  Map<String, dynamic>? _parsed;
  File? _imageFile;
  Position? _position;
  String? _address;

  final List<Map<String, dynamic>> _records = [];

  final String _systemPrompt = '''
  【嚴格指令】：
  1. 根據使用者的描述，將生態樣區調查資料萃取成 JSON 格式。
  2. 數值請僅保留數字，不需要附帶單位（單位已在 Key 中標示）。
  3. 若使用者未提及某個欄位，請填入 "" (空字串) 或 null。
  4. 選擇題或特定選項請務必參考對應的範圍。
  5. 請將輸出格式攤平 (Flatten) 為單層 JSON 物件。

  請依照以下欄位結構填寫：
  {
    "樣區編號": String, "調查人員": String, "日期": String, "時間": String, "海拔高度 (m)": Number,
    "步道距離": String ("<5m", "5-10m", ">10m"),
    "空氣溫度 (°C)": Number, "空氣相對溼度 (%)": Number, "岩石地比例 (%)": Number,
    "地表裸露度 (土的比例) (%)": Number, "凋落物覆蓋度 (無植被處) (%)": Number, "倒木覆蓋度 (%)": Number,
    "坡向": String, "坡度 (度)": Number, "土壤深度 (cm)": Number, "土壤含水量 (%)": Number,
    "土壤 pH": Number, "半球攝影": String, "備註": String,
    "樣區內_總株數": Number, "植物_編號": String, "植物_葉高 (cm)": Number, "植物_花高 (cm)": Number,
    "植物_物候": String (複選逗號隔開：種子萌芽, 塊莖萌芽, 展葉, 花苞, 雄花開, 雄花謝, 初果, 轉紅, 轉藍),
    "伴生植物_物種": String, "伴生植物_階層": String (T1, T2, S, H),
    "伴生植物_高度 (m)": Number, "伴生植物_覆蓋度 (%)": Number
  }
  只回傳 JSON 物件。
  ''';

  // ====== ① 上傳音檔 ======
  Future<void> _pickAudioFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.audio, // 限制只能選音檔 (mp3, wav, m4a...)
    );

    if (result != null) {
      setState(() {
        _audioFileName = result.files.single.name;
        _lastFilePath = result.files.single.path;

        // 網頁版會直接拿到 bytes，手機版則需透過 path 讀取
        if (result.files.single.bytes != null) {
          _audioBytes = result.files.single.bytes;
        } else if (_lastFilePath != null) {
          _audioBytes = File(_lastFilePath!).readAsBytesSync();
        }
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('已選擇音檔：$_audioFileName')));
      }
    }
  }

  // ====== ① 錄音 ======
  Future<void> _toggleRecord() async {
    if (_isRecording) {
      final path = await _recorder.stop();
      if (path != null) {
        setState(() {
          _isRecording = false;
          _lastFilePath = path;
          _audioFileName = path.split('/').last;
        });

        // 嘗試讀取為 bytes（支援後續轉譯）
        try {
          if (!kIsWeb) _audioBytes = await File(path).readAsBytes();
        } catch (_) {}

        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('錄音已儲存：$_audioFileName')));
        }
      }
      return;
    }

    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      if (context.mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('需要麥克風權限')));
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

  // ====== ★ 新增：將音檔轉換為文字 (逐字稿) ======
  Future<void> _transcribeAudio() async {
    if (_audioBytes == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('請先錄音或上傳音檔')));
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final aiModel = prefs.getString('selected_ai_model') ?? 'Gemini';
    final apiKey = prefs.getString('${aiModel.toLowerCase()}_api_key') ?? '';

    if (apiKey.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('請先設定 $aiModel 的 API Key')));
      return;
    }

    setState(() => _isTranscribing = true);

    try {
      String transcribedText = '';

      if (aiModel == 'Gemini') {
        // Gemini 支援直接把音檔當作多媒體輸入
        final model =
            GenerativeModel(model: 'gemini-2.5-flash', apiKey: apiKey);
        final response = await model.generateContent([
          Content.multi([
            TextPart('請將這段錄音轉換為逐字稿，請只輸出聽到的文字內容，不需要任何額外的解釋或問候。'),
            DataPart('audio/mp3', _audioBytes!), // 這裡標註 mime-type，大部分音檔都適用
          ])
        ]);
        transcribedText = response.text ?? '';
      } else if (aiModel == 'OpenAI') {
        // OpenAI 使用 Whisper API 進行轉譯
        var request = http.MultipartRequest('POST',
            Uri.parse('https://api.openai.com/v1/audio/transcriptions'));
        request.headers['Authorization'] = 'Bearer $apiKey';
        request.fields['model'] = 'whisper-1';
        request.files.add(http.MultipartFile.fromBytes('file', _audioBytes!,
            filename: 'audio.m4a'));

        var response = await request.send();
        var responseData = await response.stream.bytesToString();
        var json = jsonDecode(responseData);
        transcribedText = json['text'] ?? '';
      } else {
        throw Exception('Claude 目前不支援直接匯入音檔轉文字，請改用 Gemini 或 OpenAI。');
      }

      setState(() {
        _transcriptionController.text = transcribedText;
        // ★ 自動將結果填入第二區塊的輸入框！
        _inputController.text = transcribedText;
      });
    } catch (e) {
      if (context.mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('轉譯失敗: $e')));
    } finally {
      setState(() => _isTranscribing = false);
    }
  }

  // ====== ② 核心：動態呼叫 AI 萃取表格 ======
  Future<void> _parseTextWithAI() async {
    final text = _inputController.text;
    if (text.trim().isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final aiModel = prefs.getString('selected_ai_model') ?? 'Gemini';
    final apiKey = prefs.getString('${aiModel.toLowerCase()}_api_key') ?? '';

    if (apiKey.isEmpty) {
      if (context.mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('請先點擊右上角 ⚙️ 設定 API Key')));
      return;
    }

    setState(() {
      _isAnalyzing = true;
      _parsed = null;
    });

    try {
      String jsonResponseStr = '';

      if (aiModel == 'Gemini') {
        final model = GenerativeModel(
          model: 'gemini-2.5-flash',
          apiKey: apiKey,
          generationConfig:
              GenerationConfig(responseMimeType: 'application/json'),
        );
        final response = await model
            .generateContent([Content.text('$_systemPrompt\n使用者描述：\n"$text"')]);
        jsonResponseStr = response.text ?? '';
      } else if (aiModel == 'OpenAI') {
        final response = await http.post(
          Uri.parse('https://api.openai.com/v1/chat/completions'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $apiKey'
          },
          body: jsonEncode({
            'model': 'gpt-4o-mini',
            'response_format': {"type": "json_object"},
            'messages': [
              {'role': 'system', 'content': _systemPrompt},
              {'role': 'user', 'content': text}
            ]
          }),
        );
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        jsonResponseStr = data['choices'][0]['message']['content'];
      } else if (aiModel == 'Claude') {
        final response = await http.post(
          Uri.parse('https://api.anthropic.com/v1/messages'),
          headers: {
            'x-api-key': apiKey,
            'anthropic-version': '2023-06-01',
            'content-type': 'application/json'
          },
          body: jsonEncode({
            'model': 'claude-3-haiku-20240307',
            'max_tokens': 1000,
            'system': _systemPrompt,
            'messages': [
              {'role': 'user', 'content': text}
            ]
          }),
        );
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        jsonResponseStr = data['content'][0]['text'];
      }

      if (jsonResponseStr.isNotEmpty) {
        final Map<String, dynamic> jsonResult = jsonDecode(jsonResponseStr);
        jsonResult['原文'] = text;
        setState(() => _parsed = jsonResult);
      }
    } catch (e) {
      if (context.mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$aiModel 萃取失敗: $e')));
    } finally {
      setState(() => _isAnalyzing = false);
    }
  }

  // ====== 拍照 / 定位 ======
  Future<void> _takePhoto() async {
    final x = await ImagePicker()
        .pickImage(source: ImageSource.camera, imageQuality: 85);
    if (x != null) setState(() => _imageFile = File(x.path));
  }

  Future<void> _pickFromGallery() async {
    final x = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (x != null) setState(() => _imageFile = File(x.path));
  }

  Future<void> _getLocation() async {
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied)
      perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) return;
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

  // ====== 清單與匯出保持不變 ======
  void _addCurrentRecord() {
    if (_parsed == null) return;
    final withMeta = {
      '系統時間': DateTime.now().toIso8601String(),
      ..._parsed!,
      'Image path': _imageFile?.path ?? '',
      'Latitude': _position?.latitude,
      'Longitude': _position?.longitude,
      'Horizontal accuracy (m)': _position?.accuracy,
      'Address': _address ?? '',
      'Audio file path': _audioFileName ?? '',
    };
    _records.add(withMeta);
    setState(() {});
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已加入清單')));
  }

  Future<void> _exportCsv() async {
    if (_records.isEmpty && _parsed == null) return;
    final list = _records.isNotEmpty
        ? _records
        : [
            {'系統時間': DateTime.now().toIso8601String(), ...?_parsed}
          ];
    final headers = <String>{
      '系統時間',
      '樣區編號',
      '調查人員',
      '日期',
      '時間',
      '海拔高度 (m)',
      '步道距離',
      '空氣溫度 (°C)',
      '空氣相對溼度 (%)',
      '岩石地比例 (%)',
      '地表裸露度 (土的比例) (%)',
      '凋落物覆蓋度 (無植被處) (%)',
      '倒木覆蓋度 (%)',
      '坡向',
      '坡度 (度)',
      '土壤深度 (cm)',
      '土壤含水量 (%)',
      '土壤 pH',
      '半球攝影',
      '備註',
      '樣區內_總株數',
      '植物_編號',
      '植物_葉高 (cm)',
      '植物_花高 (cm)',
      '植物_物候',
      '伴生植物_物種',
      '伴生植物_階層',
      '伴生植物_高度 (m)',
      '伴生植物_覆蓋度 (%)',
      '原文'
    }.toList();
    final buffer = StringBuffer();
    buffer.write('\uFEFF');
    buffer.writeln(headers.join(','));
    for (final row in list) {
      buffer.writeln(headers
          .map((h) => '"${row[h]?.toString().replaceAll('"', '""') ?? ''}"')
          .join(','));
    }
    final file = File(
        '${(await getApplicationDocumentsDirectory()).path}/survey_${DateTime.now().millisecondsSinceEpoch}.csv');
    await file.writeAsString(buffer.toString());
    await Share.shareXFiles([XFile(file.path)], text: 'Export CSV');
  }

  Future<void> _exportTsv() async {
    if (_records.isEmpty && _parsed == null) return;
    final list = _records.isNotEmpty
        ? _records
        : [
            {'系統時間': DateTime.now().toIso8601String(), ...?_parsed}
          ];
    final headers = <String>{
      '系統時間',
      '樣區編號',
      '調查人員',
      '日期',
      '時間',
      '海拔高度 (m)',
      '步道距離',
      '空氣溫度 (°C)',
      '空氣相對溼度 (%)',
      '岩石地比例 (%)',
      '地表裸露度 (土的比例) (%)',
      '凋落物覆蓋度 (無植被處) (%)',
      '倒木覆蓋度 (%)',
      '坡向',
      '坡度 (度)',
      '土壤深度 (cm)',
      '土壤含水量 (%)',
      '土壤 pH',
      '半球攝影',
      '備註',
      '樣區內_總株數',
      '植物_編號',
      '植物_葉高 (cm)',
      '植物_花高 (cm)',
      '植物_物候',
      '伴生植物_物種',
      '伴生植物_階層',
      '伴生植物_高度 (m)',
      '伴生植物_覆蓋度 (%)',
      '原文'
    }.toList();
    final buffer = StringBuffer();
    buffer.write('\uFEFF');
    buffer.writeln(headers.join('\t'));
    for (final row in list) {
      buffer.writeln(headers
          .map((h) => (row[h]?.toString() ?? '')
              .replaceAll('\t', ' ')
              .replaceAll('\n', ' '))
          .join('\t'));
    }
    final file = File(
        '${(await getApplicationDocumentsDirectory()).path}/survey_${DateTime.now().millisecondsSinceEpoch}.tsv');
    await file.writeAsString(buffer.toString());
    await Share.shareXFiles([XFile(file.path)], text: 'Export TSV');
  }

  @override
  Widget build(BuildContext context) {
    final parsedRows = _parsed?.entries
            .map((e) => DataRow(cells: [
                  DataCell(Text(e.key)),
                  DataCell(Text('${e.value ?? ''}'))
                ]))
            .toList() ??
        [];
    final List<DataRow> tableRows = [
      DataRow(cells: [
        const DataCell(Text('現場照片')),
        DataCell(_imageFile != null
            ? Image.file(_imageFile!, width: 80, height: 80, fit: BoxFit.cover)
            : const Text('（未選擇）'))
      ]),
      DataRow(cells: [
        const DataCell(Text('GPS 座標')),
        DataCell(Text(_position != null
            ? '${_position!.latitude.toStringAsFixed(6)}, ${_position!.longitude.toStringAsFixed(6)}'
            : '（未取得）'))
      ]),
      ...parsedRows,
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('生態樣區語音辨識系統'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '設定 AI 引擎',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (context) => const SettingsPage())),
          ),
        ],
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
                    const Text('① 現場紀錄工具 (錄音/上傳音檔)',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _toggleRecord,
                          icon: Icon(_isRecording ? Icons.stop : Icons.mic),
                          label: Text(_isRecording ? '停止錄音' : '開始錄音'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isRecording ? Colors.red : null,
                            foregroundColor: _isRecording ? Colors.white : null,
                          ),
                        ),
                        // ★ 新增：上傳音檔按鈕
                        ElevatedButton.icon(
                          onPressed: _pickAudioFile,
                          icon: const Icon(Icons.upload_file),
                          label: const Text('上傳音檔 (MP3/WAV)'),
                        ),
                      ],
                    ),
                    if (_audioFileName != null) ...[
                      const SizedBox(height: 8),
                      Text('目前音檔：$_audioFileName',
                          style: const TextStyle(
                              color: Colors.blue, fontWeight: FontWeight.w500)),
                    ],
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    const Text('音檔轉譯 (逐字稿檢查與修改)',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),

                    // ★ 新增：一鍵將音檔轉為逐字稿的按鈕
                    FilledButton.icon(
                      onPressed: (_audioBytes == null || _isTranscribing)
                          ? null
                          : _transcribeAudio,
                      icon: _isTranscribing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.transcribe),
                      label: Text(_isTranscribing ? 'AI 聆聽中...' : '音檔轉成逐字稿'),
                      style:
                          FilledButton.styleFrom(backgroundColor: Colors.teal),
                    ),
                    const SizedBox(height: 12),

                    // ★ 新增：逐字稿文字框（可以在這裡確認與修改）
                    TextField(
                      controller: _transcriptionController,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: '音檔的逐字稿會顯示在這裡，您也可以手動修改...',
                      ),
                      onChanged: (value) {
                        // 如果手動修改逐字稿，自動連動到第二區塊
                        _inputController.text = value;
                      },
                    ),

                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                            onPressed: _takePhoto,
                            icon: const Icon(Icons.photo_camera),
                            label: const Text('拍照')),
                        OutlinedButton.icon(
                            onPressed: _pickFromGallery,
                            icon: const Icon(Icons.photo_library),
                            label: const Text('選圖')),
                        OutlinedButton.icon(
                            onPressed: _getLocation,
                            icon: const Icon(Icons.my_location),
                            label: const Text('取得位置')),
                      ],
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
                    const Text('② 調查口述內容 (送出萃取表格)',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _inputController,
                      maxLines: 6,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: '這裡的內容會從第一區塊自動連動填寫，您可以做最後的補充...',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                        onPressed: _isAnalyzing ? null : _parseTextWithAI,
                        icon: _isAnalyzing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.auto_awesome),
                        label: Text(_isAnalyzing ? 'AI 萃取中...' : '萃取欄位 → 產生表格'),
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
                      const Text('③ 萃取結果預覽',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(columns: const [
                          DataColumn(label: Text('調查欄位')),
                          DataColumn(label: Text('紀錄數值'))
                        ], rows: tableRows),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                              onPressed: _addCurrentRecord,
                              icon: const Icon(Icons.add),
                              label: const Text('儲存並加入清單')),
                          OutlinedButton.icon(
                              onPressed: _exportCsv,
                              icon: const Icon(Icons.file_download),
                              label: Text('匯出 CSV（${_records.length}）')),
                          OutlinedButton.icon(
                              onPressed: _exportTsv,
                              icon: const Icon(Icons.table_chart),
                              label: Text('匯出 TSV（${_records.length}）')),
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
                                '• 樣區：${r['樣區編號'] ?? '-'} ｜ 植物編號：${r['植物_編號'] ?? '-'}'),
                          )),
                    ]),
              ),
            ),
        ],
      ),
    );
  }
}
