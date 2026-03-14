import 'package:shared_preferences/shared_preferences.dart';

/// Service for persisting user settings like API keys and model preferences.
class SettingsService {
  static const String _keyGeminiApiKey = 'gemini_api_key';
  static const String _keyGeminiModel = 'gemini_model';
  static const String _keyLlmProvider = 'llm_provider';
  static const String _keyLlmBaseUrl = 'llm_base_url';
  static const String _keyTargetLanguage = 'target_language';
  static const String _keyBilingual = 'bilingual';
  static const String _keyBatchSize = 'batch_size';

  final SharedPreferences _prefs;

  SettingsService(this._prefs);

  static Future<SettingsService> init() async {
    final prefs = await SharedPreferences.getInstance();
    return SettingsService(prefs);
  }

  String get geminiApiKey => _prefs.getString(_keyGeminiApiKey) ?? '';
  Future<void> setGeminiApiKey(String value) =>
      _prefs.setString(_keyGeminiApiKey, value);

  String get geminiModel =>
      _prefs.getString(_keyGeminiModel) ?? 'gemini-2.0-flash';
  Future<void> setGeminiModel(String value) =>
      _prefs.setString(_keyGeminiModel, value);

  String get llmProvider => _prefs.getString(_keyLlmProvider) ?? 'google';
  Future<void> setLlmProvider(String value) =>
      _prefs.setString(_keyLlmProvider, value);

  String get llmBaseUrl =>
      _prefs.getString(_keyLlmBaseUrl) ??
      'https://generativelanguage.googleapis.com/v1beta/openai';
  Future<void> setLlmBaseUrl(String value) =>
      _prefs.setString(_keyLlmBaseUrl, value);

  String get targetLanguage => _prefs.getString(_keyTargetLanguage) ?? 'zh';
  Future<void> setTargetLanguage(String value) =>
      _prefs.setString(_keyTargetLanguage, value);

  bool get bilingual => _prefs.getBool(_keyBilingual) ?? true;
  Future<void> setBilingual(bool value) => _prefs.setBool(_keyBilingual, value);

  int get batchSize => _prefs.getInt(_keyBatchSize) ?? 25;
  Future<void> setBatchSize(int value) => _prefs.setInt(_keyBatchSize, value);
}
