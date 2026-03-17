/// Abstract interface for LLM translation providers.
///
/// All LLM API implementations (Gemini, OpenAI, Claude, etc.) should
/// implement this interface to allow seamless switching between providers.
///
/// Example of adding a new provider:
/// ```dart
/// class OpenAIProvider implements TranslationProvider {
///   @override
///   String get name => 'OpenAI';
///   // ... implement other methods
/// }
/// ```
abstract class TranslationProvider {
  /// Display name of this provider (e.g., "Google Gemini", "OpenAI").
  String get name;

  /// Translate a batch of texts with optional context.
  ///
  /// [texts] — the subtitle lines to translate in this batch.
  /// [contextBefore] — preceding subtitle lines for context (not to be translated).
  /// [contextAfter] — following subtitle lines for context (not to be translated).
  /// [sourceLanguage] / [targetLanguage] — language codes.
  /// [glossary] — key term mappings from prior batches for consistency.
  /// [onProgress] — progress callback (completed, total).
  /// [abortTrigger] — completes to cancel any in-flight request.
  Future<List<String>> translateBatch({
    required List<String> texts,
    required String sourceLanguage,
    required String targetLanguage,
    String? model,
    List<String> contextBefore = const [],
    List<String> contextAfter = const [],
    Map<String, String> glossary = const {},
    void Function(int completed, int total)? onProgress,
    Future<void>? abortTrigger,
  });

  /// Build a summary of the full transcript for establishing global context.
  ///
  /// This summary is sent before the first batch to help the LLM understand
  /// the overall content, tone, and terminology.
  Future<String> buildContextSummary({
    required List<String> allTexts,
    required String sourceLanguage,
    required String targetLanguage,
    String? model,
    Future<void>? abortTrigger,
  });

  /// Validate that the API key is valid and the service is reachable.
  Future<bool> validateApiKey(String apiKey, {String? model, String? baseUrl});

  /// List available models for this provider.
  Future<List<String>> listModels(String apiKey, {String? baseUrl});

  /// Release any resources held by this provider.
  void dispose();
}

/// Exception thrown when a translation is aborted by the user.
class TranslationAbortedException implements Exception {
  final String message;
  const TranslationAbortedException([this.message = 'Translation cancelled']);

  @override
  String toString() => message;
}
