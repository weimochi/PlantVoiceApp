import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final List<String> _aiModels = ['Gemini', 'OpenAI', 'Claude'];
  String _selectedModel = 'Gemini';

  final TextEditingController _apiKeyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedModel = prefs.getString('selected_ai_model') ?? 'Gemini';
      _apiKeyController.text =
          prefs.getString('${_selectedModel.toLowerCase()}_api_key') ?? '';
    });
  }

  Future<void> _onModelChanged(String? newModel) async {
    if (newModel == null) return;
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedModel = newModel;
      _apiKeyController.text =
          prefs.getString('${_selectedModel.toLowerCase()}_api_key') ?? '';
    });
  }

  // ====== 儲存金鑰 ======
  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_ai_model', _selectedModel);
    await prefs.setString('${_selectedModel.toLowerCase()}_api_key',
        _apiKeyController.text.trim());

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$_selectedModel 金鑰已安全儲存於本機！')),
      );
    }
  }

  // ====== 🌟 新增：徹底清除金鑰 ======
  Future<void> _clearSettings() async {
    final prefs = await SharedPreferences.getInstance();
    // 從本機徹底刪除該模型的 Key
    await prefs.remove('${_selectedModel.toLowerCase()}_api_key');

    setState(() {
      _apiKeyController.clear(); // 清空畫面上的輸入框
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$_selectedModel 金鑰已徹底銷毀 🗑️'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _pasteFromClipboard() async {
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    if (clipboardData != null && clipboardData.text != null) {
      setState(() {
        _apiKeyController.text = clipboardData.text!;
      });
    }
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('設定與隱私'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '請選擇你要使用的 AI 引擎，金鑰僅會儲存於您的本機裝置中：',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),

            DropdownButtonFormField<String>(
              value: _selectedModel,
              decoration: const InputDecoration(
                labelText: 'AI 引擎',
                border: OutlineInputBorder(),
              ),
              items: _aiModels.map((String model) {
                return DropdownMenuItem<String>(
                  value: model,
                  child: Text(model),
                );
              }).toList(),
              onChanged: _onModelChanged,
            ),

            const SizedBox(height: 24),

            TextField(
              controller: _apiKeyController,
              decoration: InputDecoration(
                labelText: '$_selectedModel API Key',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.content_paste),
                  tooltip: '從剪貼簿貼上',
                  onPressed: _pasteFromClipboard,
                ),
              ),
              obscureText: true,
            ),

            const SizedBox(height: 32),

            // 🌟 將按鈕改成並排：一個儲存，一個清除
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _saveSettings,
                    icon: const Icon(Icons.save),
                    label: const Text('儲存'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _clearSettings,
                    icon: const Icon(Icons.delete_forever),
                    label: const Text('清除金鑰'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
