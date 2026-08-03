import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const String _keyApiKey = 'gemini_api_key';

  // 取得儲存的 API Key
  Future<String?> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyApiKey);
  }

  // 儲存 API Key
  Future<void> saveApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyApiKey, key);
  }
}