/// Application-wide constants.
class AppConstants {
  AppConstants._();

  static const String appName = 'Caption Trans';

  /// Supported Whisper models with their approximate sizes.
  static const Map<String, String> whisperModels = {
    'tiny': 'Tiny (~75 MB)',
    'base': 'Base (~148 MB)',
    'small': 'Small (~488 MB)',
    'medium': 'Medium (~1.5 GB)',
    'large-v3': 'Large V3 (~3 GB)',
    'large-v3-turbo': 'Large V3 Turbo (~1.6 GB)',
  };

  static const String defaultWhisperModel = 'base';

  /// Hugging Face model base URL for GGML models.
  static const String whisperModelBaseUrl =
      'https://huggingface.co/ggerganov/whisper.cpp/resolve/main';

  /// Supported languages for translation target.
  static const Map<String, String> supportedLanguages = {
    'zh': '中文',
    'en': 'English',
    'ja': '日本語',
    'ko': '한국어',
    'fr': 'Français',
    'de': 'Deutsch',
    'es': 'Español',
    'pt': 'Português',
    'ru': 'Русский',
    'ar': 'العربية',
  };

  /// Supported video file extensions.
  static const List<String> videoExtensions = [
    'mp4',
    'mkv',
    'avi',
    'mov',
    'wmv',
    'flv',
    'webm',
    'm4v',
  ];
}
