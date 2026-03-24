import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/whisper_download_source.dart';

class ProviderCredential {
  final String baseUrl;
  final String apiKey;

  const ProviderCredential({required this.baseUrl, required this.apiKey});

  Map<String, String> toJson() => {'baseUrl': baseUrl, 'apiKey': apiKey};

  factory ProviderCredential.fromJson(Map<String, dynamic> json) {
    return ProviderCredential(
      baseUrl: json['baseUrl'] as String? ?? '',
      apiKey: json['apiKey'] as String? ?? '',
    );
  }
}

/// Service for persisting user settings like API keys and model preferences.
class SettingsService {
  static const String _keyGeminiApiKey = 'gemini_api_key';
  static const String _keyGeminiModel = 'gemini_model';
  static const String _keyLlmProvider = 'llm_provider';
  static const String _keyLlmBaseUrl = 'llm_base_url';
  static const String _keyLlmProviderCredentials = 'llm_provider_credentials';
  static const String _keyTargetLanguage = 'target_language';
  static const String _keyBilingual = 'bilingual';
  static const String _keyBatchSize = 'batch_size';
  static const String _keyLastUpdateCheckAt = 'last_update_check_at';
  static const String _keyWhisperDownloadSource = 'whisper_download_source';
  static const String _keyAListBaseUrl = 'alist_base_url';
  static const String _keyAListUsername = 'alist_username';
  static const String _keyAListPassword = 'alist_password';
  static const String _keyAListBrowsePath = 'alist_browse_path';
  static const String _keyAListUploadRemoteBase = 'alist_upload_remote_base';
  static const String _keyAListAudioOutputDir = 'alist_audio_output_dir';
  static const String _keyAListAudioFormat = 'alist_audio_format';
  static const String _keyAListAudioConcurrency = 'alist_audio_concurrency';
  static const String _keyAListMinVideoSizeMB = 'alist_min_video_size_mb';
  static const String _keyAListBlockedVideoNames = 'alist_blocked_video_names';

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

  String get llmProvider {
    final provider = _prefs.getString(_keyLlmProvider);
    if (provider == null || provider.isEmpty || provider == 'google') {
      return 'Gemini (Google)';
    }
    return provider;
  }

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

  DateTime? get lastUpdateCheckAt {
    final timestamp = _prefs.getInt(_keyLastUpdateCheckAt);
    if (timestamp == null || timestamp <= 0) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  }

  Future<void> setLastUpdateCheckAt(DateTime value) =>
      _prefs.setInt(_keyLastUpdateCheckAt, value.millisecondsSinceEpoch);

  WhisperDownloadSource? get whisperDownloadSource =>
      WhisperDownloadSource.tryParse(
        _prefs.getString(_keyWhisperDownloadSource),
      );

  Future<void> setWhisperDownloadSource(WhisperDownloadSource value) =>
      _prefs.setString(_keyWhisperDownloadSource, value.id);

  Future<void> clearWhisperDownloadSource() =>
      _prefs.remove(_keyWhisperDownloadSource);

  String get alistBaseUrl => _prefs.getString(_keyAListBaseUrl) ?? '';
  Future<void> setAListBaseUrl(String value) =>
      _prefs.setString(_keyAListBaseUrl, value);

  String get alistUsername => _prefs.getString(_keyAListUsername) ?? '';
  Future<void> setAListUsername(String value) =>
      _prefs.setString(_keyAListUsername, value);

  String get alistPassword => _prefs.getString(_keyAListPassword) ?? '';
  Future<void> setAListPassword(String value) =>
      _prefs.setString(_keyAListPassword, value);

  String get alistBrowsePath => _prefs.getString(_keyAListBrowsePath) ?? '/';
  Future<void> setAListBrowsePath(String value) =>
      _prefs.setString(_keyAListBrowsePath, value);

  String get alistUploadRemoteBase =>
      _prefs.getString(_keyAListUploadRemoteBase) ?? '/';
  Future<void> setAListUploadRemoteBase(String value) =>
      _prefs.setString(_keyAListUploadRemoteBase, value);

  String get alistAudioOutputDir =>
      _prefs.getString(_keyAListAudioOutputDir) ?? '';
  Future<void> setAListAudioOutputDir(String value) =>
      _prefs.setString(_keyAListAudioOutputDir, value);

  String get alistAudioFormat =>
      _prefs.getString(_keyAListAudioFormat) ?? 'flac';
  Future<void> setAListAudioFormat(String value) =>
      _prefs.setString(_keyAListAudioFormat, value);

  int get alistAudioConcurrency =>
      _prefs.getInt(_keyAListAudioConcurrency) ?? 2;
  Future<void> setAListAudioConcurrency(int value) =>
      _prefs.setInt(_keyAListAudioConcurrency, value);

  int get alistMinVideoSizeMB => _prefs.getInt(_keyAListMinVideoSizeMB) ?? 50;
  Future<void> setAListMinVideoSizeMB(int value) =>
      _prefs.setInt(_keyAListMinVideoSizeMB, value);

  String get alistBlockedVideoNames =>
      _prefs.getString(_keyAListBlockedVideoNames) ??
      '台 妹 子 線 上 現 場 直 播 各 式 花 式 表 演.mp4\n社 區 最 新 情 報.mp4';
  Future<void> setAListBlockedVideoNames(String value) =>
      _prefs.setString(_keyAListBlockedVideoNames, value);

  Map<String, ProviderCredential> get llmProviderCredentials {
    final raw = _prefs.getString(_keyLlmProviderCredentials);
    if (raw == null || raw.isEmpty) return {};

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return {};
      return decoded.map((provider, value) {
        if (value is! Map<String, dynamic>) {
          return MapEntry(
            provider,
            const ProviderCredential(baseUrl: '', apiKey: ''),
          );
        }
        return MapEntry(provider, ProviderCredential.fromJson(value));
      });
    } catch (_) {
      return {};
    }
  }

  Future<void> saveLlmProviderCredential(
    String provider,
    ProviderCredential credential,
  ) async {
    final credentials = Map<String, ProviderCredential>.from(
      llmProviderCredentials,
    );
    credentials[provider] = credential;
    await _prefs.setString(
      _keyLlmProviderCredentials,
      jsonEncode(
        credentials.map((key, value) => MapEntry(key, value.toJson())),
      ),
    );
  }

  Future<void> deleteLlmProviderCredential(String provider) async {
    final credentials = Map<String, ProviderCredential>.from(
      llmProviderCredentials,
    );
    credentials.remove(provider);
    await _prefs.setString(
      _keyLlmProviderCredentials,
      jsonEncode(
        credentials.map((key, value) => MapEntry(key, value.toJson())),
      ),
    );
  }
}
